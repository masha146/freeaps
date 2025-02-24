import Disk
import Foundation

protocol FileStorage {
    func save<Value: JSON>(_ value: Value, as name: String)
    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value?
    func retrieveRaw(_ name: String) -> RawJSON?
    func append<Value: JSON>(_ newValue: Value, to name: String)
    func append<Value: JSON>(_ newValues: [Value], to name: String)
    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>)
    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>)
    func remove(_ name: String)
    func rename(_ name: String, to newName: String)
    func transaction(_ exec: (FileStorage) -> Void)

    func urlFor(file: String) -> URL?
}

final class BaseFileStorage: FileStorage {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseFileStorage.processQueue", qos: .utility)

    func save<Value: JSON>(_ value: Value, as name: String) {
        processQueue.safeSync {
            if let value = value as? RawJSON, let data = value.data(using: .utf8) {
                try? Disk.save(data, to: .documents, as: name)
            } else {
                try? Disk.save(value, to: .documents, as: name, encoder: JSONCoding.encoder)
            }
        }
    }

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value? {
        processQueue.safeSync {
            try? Disk.retrieve(name, from: .documents, as: type, decoder: JSONCoding.decoder)
        }
    }

    func retrieveRaw(_ name: String) -> RawJSON? {
        processQueue.safeSync {
            guard let data = try? Disk.retrieve(name, from: .documents, as: Data.self) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
    }

    func append<Value: JSON>(_ newValue: Value, to name: String) {
        processQueue.safeSync {
            try? Disk.append(newValue, to: name, in: .documents, decoder: JSONCoding.decoder, encoder: JSONCoding.encoder)
        }
    }

    func append<Value: JSON>(_ newValues: [Value], to name: String) {
        processQueue.safeSync {
            try? Disk.append(newValues, to: name, in: .documents, decoder: JSONCoding.decoder, encoder: JSONCoding.encoder)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>) {
        if let value = retrieve(name, as: Value.self) {
            if value[keyPath: keyPath] != newValue[keyPath: keyPath] {
                append(newValue, to: name)
            }
        } else if let values = retrieve(name, as: [Value].self) {
            guard values.first(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) == nil else {
                return
            }
            append(newValue, to: name)
        } else {
            save(newValue, as: name)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>) {
        if let value = retrieve(name, as: Value.self) {
            guard newValues.first(where: { $0[keyPath: keyPath] == value[keyPath: keyPath] }) == nil else {
                return
            }
            append(newValues, to: name)
        } else if let values = retrieve(name, as: [Value].self) {
            newValues.forEach { newValue in
                guard values.first(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) == nil else {
                    return
                }
                append(newValue, to: name)
            }
        } else {
            save(newValues, as: name)
        }
    }

    func remove(_ name: String) {
        processQueue.safeSync {
            try? Disk.remove(name, from: .documents)
        }
    }

    func rename(_ name: String, to newName: String) {
        processQueue.safeSync {
            try? Disk.rename(name, in: .documents, to: newName)
        }
    }

    func transaction(_ exec: (FileStorage) -> Void) {
        processQueue.safeSync {
            exec(self)
        }
    }

    func urlFor(file: String) -> URL? {
        try? Disk.url(for: file, in: .documents)
    }
}
