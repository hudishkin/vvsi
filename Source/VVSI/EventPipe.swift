import Combine

private final class SendableCancellable: @unchecked Sendable {
    private let cancellable: AnyCancellable

    init(_ cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        cancellable.cancel()
    }
}

/// Shared event pipe: Interactor sends, View observes via publisher and/or AsyncStream.
public final class EventPipe<Event: EventProtocol>: @unchecked Sendable {

    private let subject = PassthroughSubject<Event, Never>()

    public init() {}

    public var publisher: AnyPublisher<Event, Never> {
        subject.eraseToAnyPublisher()
    }

    public func stream(
        bufferingPolicy: AsyncStream<Event>.Continuation.BufferingPolicy = .bufferingNewest(1)
    ) -> AsyncStream<Event> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let cancellable = SendableCancellable(subject.sink(
                receiveCompletion: { _ in continuation.finish() },
                receiveValue: { continuation.yield($0) }
            ))
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    public func send(_ event: Event) {
        subject.send(event)
    }
}
