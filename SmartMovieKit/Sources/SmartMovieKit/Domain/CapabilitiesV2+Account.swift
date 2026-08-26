public extension CapabilitiesV2 {
    func supportsAccountAuthentication(mode: String) -> Bool {
        switch mode {
        case "browser", "web": supportsAccount("browser_auth")
        case "tv": supportsAccount("tv_qr_auth")
        default: false
        }
    }
}
