import Foundation

fileprivate enum Endpoint: String {
    case initialize = "/v1/initialize"
    case logEvent = "/v1/rgstr"
}

fileprivate typealias NetworkCompletionHandler = (Data?, URLResponse?, Error?) -> Void
fileprivate typealias TaskCaptureHandler = ((URLSessionDataTask) -> Void)?

class NetworkService {
    let sdkKey: String
    let statsigOptions: StatsigOptions
    var store: InternalStore

    private final let apiHost = "api.statsig.com"
    private final let networkRetryErrorCodes = [408, 500, 502, 503, 504, 522, 524, 599]

    init(sdkKey: String, options: StatsigOptions, store: InternalStore) {
        self.sdkKey = sdkKey
        self.statsigOptions = options
        self.store = store
    }

    func fetchUpdatedValues(for user: StatsigUser, lastSyncTimeForUser: Double, completion: (() -> Void)?) {
        let (body, _) = makeReqBody([
            "user": user.toDictionary(forLogging: false),
            "statsigMetadata": user.deviceEnvironment,
            "lastSyncTimeForUser": lastSyncTimeForUser
        ])

        guard let body = body else {
            completion?()
            return
        }

        let cacheKey = user.getCacheKey()
        let fullUserHash = user.getFullUserHash()

        makeAndSendRequest(.initialize, body: body) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []),
                  let dict = json as? [String: Any],
                  dict["has_updates"] as? Bool == true else {
                completion?()
                return
            }

            self.store.saveValues(dict, cacheKey, fullUserHash, completion)
        }
    }

    func fetchInitialValues(for user: StatsigUser, sinceTime: Double, completion: completionBlock) {
        var task: URLSessionDataTask?
        var done: completionBlock = nil
        done = { err in
            DispatchQueue.main.async {
                done = nil
                task?.cancel()
                completion?(err)
            }
        }

        if statsigOptions.initTimeout > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + statsigOptions.initTimeout) {
                done?("initTimeout Expired")
            }
        }

        let (body, parseErr) = makeReqBody([
            "user": user.toDictionary(forLogging: false),
            "statsigMetadata": user.deviceEnvironment,
            "sinceTime": sinceTime
        ])

        guard let body = body else {
            done?(parseErr?.localizedDescription)
            return
        }

        let cacheKey = user.getCacheKey()
        let fullUserHash = user.getFullUserHash()

        makeAndSendRequest(.initialize, body: body, retry: 3) { [weak self] data, response, error in
            if let error = error {
                done?(error.localizedDescription)
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(statusCode) {
                done?("An error occurred during fetching values for the user. \(statusCode)")
                return
            }

            guard let self = self else {
                done?("Failed to call NetworkService as it has been released")
                return
            }

            var values: [String: Any]? = nil
            if statusCode == 204 {
                values = ["has_updates": false]
            } else if let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                values = json as? [String: Any]
            }

            guard let values = values else {
                done?("No values returned with initialize response")
                return
            }

            self.store.saveValues(values, cacheKey, fullUserHash) {
                done?(nil)
            }

        } taskCapture: { capturedTask in
            task = capturedTask
        }
    }

    func sendEvents(forUser: StatsigUser, events: [Event],
                    completion: @escaping ((_ errorMessage: String?, _ data: Data?) -> Void))
    {
        let (body, parseErr) = makeReqBody([
            "events": events.map { $0.toDictionary() },
            "user": forUser.toDictionary(forLogging: true),
            "statsigMetadata": forUser.deviceEnvironment
        ])

        guard let body = body else {
            completion(parseErr?.localizedDescription, nil)
            return
        }

        makeAndSendRequest(.logEvent, body: body) { _, response, error in
            if let error = error {
                completion(error.localizedDescription, body)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                completion("An error occurred during sending events to server. "
                           + "\(String(describing: (response as? HTTPURLResponse)?.statusCode))", body)
                return
            }
        }
    }

    func sendRequestsWithData(_ dataArray: [Data], completion: @escaping ((_ failedRequestsData: [Data]?) -> Void)) {
        var failedRequests: [Data] = []
        let dispatchGroup = DispatchGroup()
        for data in dataArray {
            dispatchGroup.enter()
            makeAndSendRequest(.logEvent, body: data) { _, response, error in
                let httpResponse = response as? HTTPURLResponse
                if error != nil ||
                    (httpResponse != nil && !(200...299).contains(httpResponse!.statusCode))
                {
                    failedRequests.append(data)
                }
                dispatchGroup.leave()
            }
        }
        dispatchGroup.notify(queue: .main) {
            completion(failedRequests)
        }
    }

    private func makeReqBody(_ dict: Dictionary<String, Any>) -> (Data?, Error?) {
        if JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict){
            return (data, nil)
        }

        return (nil, StatsigError.invalidJSONParam("requestBody"))
    }

    private func makeAndSendRequest(_ endpoint: Endpoint, body: Data, retry: Int = 0, completion: @escaping NetworkCompletionHandler, taskCapture: TaskCaptureHandler = nil)
    {
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = apiHost
        urlComponents.path = endpoint.rawValue

        if let override = self.statsigOptions.overrideURL {
            urlComponents.scheme = override.scheme
            urlComponents.host = override.host
            urlComponents.port = override.port
        }

        guard let requestURL = urlComponents.url else {
            completion(nil, nil, StatsigError.invalidRequestURL("\(endpoint)"))
            return
        }

        var request = URLRequest(url: requestURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sdkKey, forHTTPHeaderField: "STATSIG-API-KEY")
        request.setValue("\(NSDate().epochTimeInMs())", forHTTPHeaderField: "STATSIG-CLIENT-TIME")
        request.httpBody = body
        request.httpMethod = "POST"

        sendRequest(request, retry: retry, completion: completion, taskCapture: taskCapture)
    }

    private func sendRequest(_ request: URLRequest, retry: Int = 0, backoff: Double = 1, completion: @escaping NetworkCompletionHandler, taskCapture: TaskCaptureHandler) {
        DispatchQueue.main.async {
            let task = URLSession.shared.dataTask(with: request) { [weak self] responseData, response, error in
                if retry > 0,
                   let self = self,
                   let statusCode = (response as? HTTPURLResponse)?.statusCode,
                   self.networkRetryErrorCodes.contains(statusCode)
                {
                    self.sendRequest(request, retry: retry - 1, backoff: backoff * 2, completion: completion, taskCapture: taskCapture)
                } else {
                    Statsig.errorBoundary.capture {
                        completion(responseData, response, error)
                    } withRecovery: {
                        completion(nil, nil, StatsigError.unexpectedError("Response Handling"))
                    }
                }

            }

            taskCapture?(task)
            task.resume()
        }
    }
}
