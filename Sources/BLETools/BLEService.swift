//
//  BLEService.swift
//  BLETools
//
//  Created by Alex - SEEMOO on 30.03.20.
//  Copyright © 2020 SEEMOO - TU Darmstadt. All rights reserved.
//

import Foundation
import CoreBluetooth

public struct BLEService: Equatable, Hashable {
    public internal(set) var uuid: CBUUID
    public internal(set) var commonName: String
    public internal(set) var isPrimary: Bool?
    public internal(set) var cbService: CBService?
    
    public var uuidString: String {
        uuid.uuidString
    }
    
    init(with cbService: CBService) {
        self.uuid = cbService.uuid
        self.cbService = cbService
        self.isPrimary = cbService.isPrimary
        self.commonName = cbService.uuid.description
    }
    
    init(with relayedService: BLERelayedService) {
        self.uuid = relayedService.uuid
        self.commonName = relayedService.commonName
    }
    
    public static func == (lhs: BLEService, rhs: BLEService) -> Bool {
        lhs.uuid.uuidString == rhs.uuid.uuidString
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid.uuidString.hashValue)
    }
}


public struct BLECharacteristic: Equatable, Hashable, CustomStringConvertible {
    public internal(set) var uuid: CBUUID
    public internal(set) var commonName: String
    public internal(set) var properties: CBCharacteristicProperties?
    public internal(set) var value: Data?
    
    
    public var description: String {
        "BLECharacteristic:\n\(String(describing: commonName)) - \(value != nil ? String(data: value!, encoding: .ascii) ?? value!.hexadecimal : "empty")"
    }
    
    init(with cbChar: CBCharacteristic, and value: Data?=nil) {
        self.uuid = cbChar.uuid
        self.commonName = cbChar.uuid.description
        self.properties = cbChar.properties
        self.value = value
    }
    
    init(with relayedCharacteristic: BLERelayCharacteristic) {
        self.uuid = relayedCharacteristic.uuid
        self.commonName = relayedCharacteristic.commonName
        self.value = relayedCharacteristic.value
    }
    
    public static func == (lhs: BLECharacteristic, rhs: BLECharacteristic) -> Bool {
        lhs.uuid.uuidString == rhs.uuid.uuidString
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid.uuidString.hashValue)
    }
}