import CoreGraphics

struct BrowserFaviconImageCacheKey: Hashable, Sendable {
    let payload: BrowserFaviconPayloadIdentity
    let maximumPixelSize: Int
}

struct BrowserFaviconImageCacheRequestLease: Sendable {
    let token: BrowserFaviconImageCacheRequestToken
    let task: Task<CGImage?, Never>
}

struct BrowserFaviconImageCacheRequestToken: Equatable, Sendable {
    let generation: UInt64
    let requestID: UInt64
}

struct BrowserFaviconImageCacheRequestRegistry {
    private var generation: UInt64 = 0
    private var nextRequestID: UInt64 = 0
    private var inFlight: [BrowserFaviconImageCacheKey: BrowserFaviconImageCacheRequestLease] = [:]

    mutating func lease(
        for key: BrowserFaviconImageCacheKey,
        createTask: () -> Task<CGImage?, Never>
    ) -> BrowserFaviconImageCacheRequestLease {
        if let lease = inFlight[key], lease.token.generation == generation {
            return lease
        }
        nextRequestID &+= 1
        let lease = BrowserFaviconImageCacheRequestLease(
            token: BrowserFaviconImageCacheRequestToken(
                generation: generation,
                requestID: nextRequestID
            ),
            task: createTask()
        )
        inFlight[key] = lease
        return lease
    }

    mutating func complete(
        _ lease: BrowserFaviconImageCacheRequestLease,
        for key: BrowserFaviconImageCacheKey
    ) -> Bool {
        guard lease.token.generation == generation,
            inFlight[key]?.token == lease.token
        else { return false }
        inFlight[key] = nil
        return true
    }

    func isCurrent(_ lease: BrowserFaviconImageCacheRequestLease) -> Bool {
        lease.token.generation == generation
    }

    mutating func removeAll() -> [BrowserFaviconImageCacheRequestLease] {
        generation &+= 1
        let pending = Array(inFlight.values)
        inFlight.removeAll(keepingCapacity: true)
        return pending
    }
}
