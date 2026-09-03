//
//  PublishedPersist.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Combine
import Foundation
import os.log

private let storeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchDrop", category: "FileStorage")

protocol PersistProvider {
    func data(forKey: String) -> Data?
    func set(_ data: Data?, forKey: String)
}

private let valueEncoder = JSONEncoder()
private let valueDecoder = JSONDecoder()
private var configDir: URL {
    documentsDirectory.appendingPathComponent("Config")
}

class FileStorage: PersistProvider {
    private let ioQueue = DispatchQueue(label: "NotchDrop.FileStorage", qos: .utility)
    private let fm = FileManager.default

    func pathForKey(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let dir = configDir
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            storeLog.error("createDirectory \(dir.path) failed: \(error.localizedDescription)")
        }
        return dir.appendingPathComponent(safe)
    }

    func data(forKey key: String) -> Data? {
        do {
            return try Data(contentsOf: pathForKey(key))
        } catch {
            storeLog.error("read \(key) failed: \(error.localizedDescription)")
            return nil
        }
    }

    func set(_ data: Data?, forKey key: String) {
        guard let data else { return }
        let path = pathForKey(key)
        ioQueue.async {
            do {
                try data.write(to: path, options: .atomic)
            } catch {
                storeLog.error("write \(key) failed: \(error.localizedDescription)")
            }
        }
    }
}

@propertyWrapper
struct Persist<Value: Codable> {
    private let subject: CurrentValueSubject<Value, Never>
    private let cancellables: Set<AnyCancellable>

    var projectedValue: AnyPublisher<Value, Never> {
        subject.eraseToAnyPublisher()
    }

    init(key: String, defaultValue: Value, engine: PersistProvider) {
        if let data = engine.data(forKey: key) {
            do {
                let object = try valueDecoder.decode(Value.self, from: data)
                subject = CurrentValueSubject<Value, Never>(object)
            } catch {
                storeLog.error("decode \(key) failed: \(error.localizedDescription), fallback to default")
                subject = CurrentValueSubject<Value, Never>(defaultValue)
            }
        } else {
            subject = CurrentValueSubject<Value, Never>(defaultValue)
        }

        var cancellables: Set<AnyCancellable> = .init()
        subject
            .receive(on: DispatchQueue.global())
            .compactMap { value -> Data? in
                do {
                    return try valueEncoder.encode(value)
                } catch {
                    storeLog.error("encode \(key) failed: \(error.localizedDescription)")
                    return nil
                }
            }
            .removeDuplicates()
            .sink { engine.set($0, forKey: key) }
            .store(in: &cancellables)
        self.cancellables = cancellables
    }

    var wrappedValue: Value {
        get { subject.value }
        set { subject.send(newValue) }
    }
}

@propertyWrapper
struct PublishedPersist<Value: Codable> {
    @Persist private var value: Value

    var projectedValue: AnyPublisher<Value, Never> { $value }

    @available(*, unavailable, message: "accessing wrappedValue will result undefined behavior")
    var wrappedValue: Value {
        get { value }
        set { value = newValue }
    }

    static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped _: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, PublishedPersist<Value>>
    ) -> Value {
        get { object[keyPath: storageKeyPath].value }
        set {
            (object.objectWillChange as? ObservableObjectPublisher)?.send()
            object[keyPath: storageKeyPath].value = newValue
        }
    }

    init(key: String, defaultValue: Value, engine: PersistProvider) {
        _value = .init(key: key, defaultValue: defaultValue, engine: engine)
    }
}

extension Persist {
    init(key: String, defaultValue: Value) {
        self.init(key: key, defaultValue: defaultValue, engine: FileStorage())
    }
}

extension PublishedPersist {
    init(key: String, defaultValue: Value) {
        self.init(key: key, defaultValue: defaultValue, engine: FileStorage())
    }
}
