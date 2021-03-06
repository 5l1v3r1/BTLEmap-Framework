//
//  AppleBLEDevice.swift
//  BLETools
//
//  Created by Alex - SEEMOO on 17.02.20.
//  Copyright © 2020 SEEMOO - TU Darmstadt. All rights reserved.
//

import Foundation
import CoreBluetooth
import Combine
import BLEDissector

public class BLEDevice: NSObject, Identifiable, ObservableObject {
    public let id: String
    private var _name: String?
    public internal(set) var name: String? {
        get {
            if let n = _name {
                return n
            }
            
            return self.peripheral?.name
        }
        set(v) {
            self._name = v
        }
    }
    @Published public private (set) var advertisements = [BLEAdvertisment]()
    
    @Published public private(set) var services = Set<BLEService>()
    
    @Published public internal(set) var isActive: Bool = false
        
    public internal(set) var peripheral: CBPeripheral?
    
    /// The UUID of the peripheral
    public var uuid: UUID {return peripheral?.identifier ?? UUID()}
    
    public private(set) var macAddress: BLEMACAddress?
    
    /// The manufacturer of this device. Mostly taken from advertisement
    public private(set) var manufacturer: BLEManufacturer {
        didSet {
            if self.manufacturer == .seemoo {
                self.deviceModel?.deviceType = .seemoo
            }
        }
    }
    
    @Published public internal(set) var deviceModel: BLEDeviceModel?
    
    
    /// Last RSSI value that has been received
    @Published public var lastRSSI: Float = -100
    
    /// All RSSI values received in sorted array. The array values are a tuple of time interval when it was received +  the RSSI as a float
    public var allRSSIs = [(time: TimeInterval, rssi: Float)]()
    
    /// True if the device marks itself as connectable
    public var connectable: Bool {
        return self.advertisements.last(where: {$0.connectable}) != nil
    }
    
    /// The last time when this device has sent an advertisement
    public private(set) var lastUpdate: Date = Date()
    
    /// Subject to which can be subscribed to receive every new advertisement individually after it has been added to the device.
    public let newAdvertisementSubject = PassthroughSubject<BLEAdvertisment, Never>()
    
    /// If available the current os version will be set. Is a string like: iOS 13 or macOS
    @Published public private(set) var osVersion: String?
    
    /// If available the state of the wifi setting will be set
    @Published public private(set) var wiFiOn: Bool?
    
    
    /// A CSV file string that contains all advertisements
    public var  advertisementCSV: String {
        self.convertAdvertisementsToCSV()
    }
    
    internal var activityTimer: Timer?
    
    init(peripheral: CBPeripheral, and advertisement: BLEAdvertisment, at time: TimeInterval) {
        
        self.peripheral = peripheral
        self._name = peripheral.name
        self.id = peripheral.identifier.uuidString
        self.manufacturer = advertisement.manufacturer
        super.init()
        self.advertisements.append(advertisement)
        self.detectOSVersion(from: advertisement)
        self.lastRSSI = advertisement.rssi.last?.floatValue ?? -100.0
        self.allRSSIs.append((time, self.lastRSSI))
    }
    
    /// Initializer for using other inputsources than CoreBluetooth. This needs a **MAC address** in the advertisement
    /// - Parameter advertisement: BLE Advertisement
    /// - Throws:Error if no **MAC address** is passed in the advertisement
    init(with advertisement: BLEAdvertisment, at time: TimeInterval) throws {
//        self._name =
        guard let macAddress = advertisement.macAddress else {
            throw Error.noMacAddress
        }
        self.id = macAddress.addressString
        self.macAddress = macAddress
        self.manufacturer = advertisement.manufacturer
        super.init()
        self.advertisements.append(advertisement)
        self.detectOSVersion(from: advertisement)
        self.lastRSSI = advertisement.rssi.last?.floatValue ?? -100.0
        self.allRSSIs.append((time, self.lastRSSI))
        self._name = advertisement.deviceName
    }
    
    public static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Add a received advertisement to the device
    /// - Parameter advertisement: received BLE advertisement
    func add(advertisement: BLEAdvertisment, time: TimeInterval) {
        // Check if that advertisement has been received before
        if let matching = self.findDuplicated(advertisement: advertisement) {
            matching.update(with: advertisement)
        }else {
            self.advertisements.append(advertisement)
        }
        
        self.lastUpdate = advertisement.receptionDates.last!
        
        self.detectOSVersion(from: advertisement)
        if let rssi = advertisement.rssi.last?.floatValue {
            self.lastRSSI = rssi
            self.allRSSIs.append((time, rssi))
        }
        
        self.isActive = true
        self.activityTimer?.invalidate()
        self.activityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { (_) in
            self.isActive = false
        }
        
        //Add device address if available
        if let deviceAddress = advertisement.deviceAddress,
            let deviceAddressType = advertisement.deviceAddressType {
            self.macAddress = BLEMACAddress(addressData: deviceAddress, addressTypeInt: deviceAddressType)
        }
    }
    
    private func findDuplicated(advertisement: BLEAdvertisment) -> BLEAdvertisment? {
        self.advertisements.first(where: { (adv) in
            adv.manufacturerData == advertisement.manufacturerData && adv.serviceData == advertisement.serviceData && adv.serviceUUIDs == advertisement.serviceUUIDs
        })
    }
    
    func addServices(services: [BLEService]) {
        self.services = Set(services)
        
    }
    
    func updateService(service: BLEService) {
        if service.uuid == CBServiceUUIDs.deviceInformation.uuid,
            let modelNumber = service.characteristics.first(where: {$0.uuid == CBCharacteristicsUUIDs.modelNumber.uuid}){
            if let modelNumberString = modelNumber.value?.stringUTF8 {
                self.deviceModel = BLEDeviceModel(modelNumberString)
            }
            
        }
        self.services.update(with: service)
    }
    
    private func detectOSVersion(from advertisement: BLEAdvertisment) {
        let nearbyInt = BLEAdvertisment.AppleAdvertisementType.nearby.rawValue
        if let nearby = advertisement.advertisementTLV?.getValue(forType: nearbyInt),
            let description = try? AppleBLEDecoding.decoder(forType: UInt8(nearbyInt)).decode(nearby),
            let wifiState = description["wiFiState"] as? AppleBLEDecoding.NearbyDecoder.DeviceFlags {
            
            switch wifiState {
            case .iOS10:
                self.osVersion = "iOS 10"
            case .iOS11:
                self.osVersion = "iOS 11"
            case .iOS12OrIPadOS13WiFiOn:
                if self.deviceModel?.deviceType == BLEDeviceModel.DeviceType.iPad {
                    self.osVersion = "iPadOS 13"
                }else {
                    self.osVersion = "iOS 12"
                }
                
                self.wiFiOn = true
            case .iOS12WiFiOn:
                if self.deviceModel?.modelName.lowercased().contains("mac") == true {
                    self.osVersion = "macOS"
                }else {
                    self.osVersion = "iOS 12"
                }
                
                self.wiFiOn = true
            case .iOS12WiFiOff:
                if self.deviceModel?.modelName.lowercased().contains("mac") == true {
                    self.osVersion = "macOS"
                }else {
                    self.osVersion = "iOS 12"
                }
                
                self.wiFiOn = false
            case .iOS12OrMacOSWifiOn:
                if self.deviceModel?.modelName.lowercased().contains("mac") == true {
                    self.osVersion = "macOS"
                }else {
                    self.osVersion = "iOS 12"
                }
                
                self.wiFiOn = true
            case .iOS13WiFiOn:
                self.osVersion = "iOS 13"
                self.wiFiOn = true
            case .iOS13WiFiOff:
                self.osVersion = "iOS 13"
                self.wiFiOn = false
            case .iOS13WifiOn2:
                self.osVersion = "iOS 13"
                self.wiFiOn = true
            case .macOSWiFiUnknown:
                self.osVersion = "macOS"
            case .macOSWiFiOn:
                self.osVersion = "macOS"
                self.wiFiOn = true
            case .watchWiFiUnknown:
                self.osVersion = "watchOS"
            case .unknown:
                break
            }
        }
    }

    
    public override var debugDescription: String {
        return(
        """
        \(self.uuid.uuidString)
        \t \(String(describing: self.name))
        \t \(self.advertisements.count) advertisements
        """)
    }
    
    func convertAdvertisementsToCSV() -> String {
        var csv = ""
        //Header
        csv += "Manufacturer data; TLV; Description"
        
        //Add hex encoded content
        let advertisementStrings = advertisements.compactMap { advertisement -> String in
            // Manufacturer data hex
            let mData = (advertisement.manufacturerData?.hexadecimal ?? "no data")
            //Formatted TLV (if it's not containing TLVs  the data will be omitted)
            let tlvString = advertisement.advertisementTLV.flatMap { tlvBox -> String  in
                tlvBox.tlvs.map { (tlv) -> String in
                    String(format: "%02x ", tlv.type) + String(format: "%02x ", tlv.length) + tlv.value.hexadecimal.separate(every: 8, with: " ")
                }.joined(separator: ", ")
                } ?? "no data"
            
            // Description for all contained TLV types
            let descriptionDicts = advertisement.advertisementTLV.flatMap { (tlvBox) -> [String] in
                // Map all TLVs to a string describing their content
                tlvBox.tlvs.map { (tlv) -> String in
                    
                    guard tlv.type != 0x4c else {return "Apple BLE"}
                    
                    let typeString = BLEAdvertisment.AppleAdvertisementType(rawValue: tlv.type)?.description ?? "Unknown type"
                    
                    let descriptionString = ((try? AppleBLEDecoding.decoder(forType: UInt8(tlv.type)).decode(tlv.value)))?.map({($0.0, $0.1)})
                        .compactMap({ (key, value) -> String in
                            if let data = value as? Data {
                                return "\(key): \t\(data.hexadecimal.separate(every: 8, with: " ")) \t"
                            }
                            
                            if let array = value as? [Any] {
                                return "\(key): \t \(array.map{String(describing: $0)}) \t"
                            }
                            
                            return "\(key):\t\(value),\t"
                            
                        }) ?? ["unknown type"]
                    
                    return typeString + "\t: " + descriptionString.joined(separator: " ")
                }
                }?.joined(separator: ",\t") ?? "no data"
            
            return mData + ";" + tlvString + ";" + descriptionDicts
        }
        csv += "\n"
        csv += advertisementStrings.joined(separator: "\n")
        return csv
    }
    
//    public override func hash(into hasher: inout Hasher) {
//        return hasher.combine(id)
//    }
    
    public enum Error: Swift.Error {
        case noMacAddress
    }
}

extension BLEDevice: CBPeripheralDelegate {
    
}
