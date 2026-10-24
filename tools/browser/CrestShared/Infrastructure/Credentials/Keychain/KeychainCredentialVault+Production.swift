extension KeychainCredentialVault {
    init(
        servicePrefix: String = CredentialKeychainNamespace.productionPrefix
    ) {
        self.init(
            store: SecurityCredentialKeychainStore(),
            servicePrefix: servicePrefix
        )
    }
}
