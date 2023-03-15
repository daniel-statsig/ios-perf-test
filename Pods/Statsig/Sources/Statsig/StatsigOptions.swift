import Foundation

/**
 Configuration options for the StatsigSDK.
 */
public class StatsigOptions {
    /**
     Used to decide how long the Statsig client waits for the initial network request to respond before calling the completion block. The Statsig client will return either cached values (if any) or default values if checkGate/getConfig/getExperiment is called before the initial network request completes
     */
    public var initTimeout = 3.0

    /**
     By default, any custom event your application logs with Statsig.logEvent() includes the current root View Controller. This is so we can generate user journey funnels for your users. You can set this parameter to true to disable this behavior.
     */
    public var disableCurrentVCLogging = false


    /**
     By default, feature values for a user are fetched once during Statsig.start and don't change throughout the session. Setting this value to true will make Statsig periodically fetch updated values for the current user.
     */
    public var enableAutoValueUpdate = false

    /**
     Overrides the auto generated StableID that is set for the device.
     */
    public var overrideStableID: String?

    /**
     Use file caching instead of UserDefaults. Useful if you are running into size limits with UserDefaults (ie tvOS)
     */
    public var enableCacheByFile = false

    internal var overrideURL: URL?
    var environment: [String: String] = [:]

    public init(initTimeout: Double? = 3.0,
                disableCurrentVCLogging: Bool? = false,
                environment: StatsigEnvironment? = nil,
                enableAutoValueUpdate: Bool? = false,
                overrideStableID: String? = nil,
                enableCacheByFile: Bool? = false)
    {
        if let initTimeout = initTimeout, initTimeout >= 0 {
            self.initTimeout = initTimeout
        }

        if let disableCurrentVCLogging = disableCurrentVCLogging {
            self.disableCurrentVCLogging = disableCurrentVCLogging
        }

        if let environment = environment {
            self.environment = environment.params
        }

        if let enableAutoValueUpdate = enableAutoValueUpdate {
            self.enableAutoValueUpdate = enableAutoValueUpdate
        }

        if let enableCacheByFile = enableCacheByFile {
            self.enableCacheByFile = enableCacheByFile
        }

        self.overrideStableID = overrideStableID
        self.overrideURL = nil
    }
}
