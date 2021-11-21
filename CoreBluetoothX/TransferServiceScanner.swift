//
//  TransferServiceScanner.swift
//  CoreBluetoothX
//
//  Created by 杨俊艺 on 2021/11/19.
//

import CoreBluetooth

protocol TransferServiceScannerDelegate: NSObjectProtocol {
    func didStartScan()
    func didStopScan()
    func didTransferData(data: NSData?)
}

// MARK: - 将中心设备视图控制器蓝牙交互细节抽到这个类中然后处理完蓝牙交互通过委托回调出去
class TransferServiceScanner: NSObject {
    
    // MARK: - 中心设备管理器
    var centralManager: CBCentralManager!
    // MARK: - 发现到的外围设备
    var discoveredPeripheral: CBPeripheral?
    // MARK: - 发送的数据？？？？
    var data: NSMutableData = NSMutableData.init()
    
    weak var delegate: TransferServiceScannerDelegate?
    
    init(delegate: TransferServiceScannerDelegate?) {
        super.init()
        
        centralManager = CBCentralManager.init(delegate: self, queue: nil)
        self.delegate = delegate
    }
    
    // MARK: - 开始扫描指定服务
    func startScan() {
        print("\(Date.init()) 1.中心控制器开始扫描感兴趣的服务")
        
        // 扫描指定的服务
        let services = [CBUUID.init(string: kTransferServiceUUID)]
        // 扫描选项
        let options = Dictionary.init(dictionaryLiteral: (CBCentralManagerScanOptionAllowDuplicatesKey, false))
//        centralManager.scanForPeripherals(withServices: nil, options: options)
        centralManager.scanForPeripherals(withServices: services, options: options)
        delegate?.didStartScan()
    }
    
    // MARK: - 停止扫描
    func stopScan() {
        print("\(Date.init()) 中心控制器停止扫描")
        centralManager.stopScan()
        delegate?.didStopScan()
    }
    
}

// MARK: - 中心设备委托
extension TransferServiceScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("\(Date.init()) 中心设备蓝牙已开启")
        case .poweredOff:
            print("\(Date.init()) 中心设备蓝牙已关闭")
            stopScan()
        default:
            print("\(Date.init()) 中心设备蓝牙已\(central.state)")
        }
    }
    
    // MARK: - 发现外围设备广播信息
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("\(Date.init()) 2发现外围设备 \(peripheral)")
        print("\(Date.init()) 广播数据是 \(advertisementData[CBAdvertisementDataServiceUUIDsKey] ?? "")")
        print("\(Date.init()) 广播数据是 \(advertisementData)")
//        if RSSI.intValue > -15 || RSSI.intValue < -40 {
//            print("\(Date.init()) 信号不在合理范围 RSSI值为 \(RSSI.intValue)")
//            return
//        }
        
        print("必须持有外围设备副本防止被Core Bluetooth处理掉")
        // 错误信息[CoreBluetooth] API MISUSE: Cancelling connection for unused peripheral Did you forget to keep a reference to it?
        if discoveredPeripheral != peripheral {
            discoveredPeripheral = peripheral
        }
        centralManager.connect(peripheral, options: nil)
        print("\(Date.init()) 3尝试连接到外围设备 \(peripheral)")
    }
    
    // MARK: - 连接上外围设备进行服务发现
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("\(Date.init()) 4已经连接上外围设备对它进行服务发现 \(peripheral)")
        stopScan()
        data.length = 0
        
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID.init(string: kTransferServiceUUID)])
    }
    
    // MARK: - 连接外围设备失败
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("\(Date.init()) 连接外围设备失败 \(peripheral)")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("\(Date.init()) 中心设备断开连接")
        self.discoveredPeripheral = nil
    }
}

// MARK: - 外围设备委托
extension TransferServiceScanner: CBPeripheralDelegate {
    // MARK: - 外围设备服务被发现
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            print("\(Date.init()) 外围设备服务发现错误 \(error?.localizedDescription ?? "")")
            return
        }
        print("\(Date.init()) 5外围设备服务被发现了")
        
        // 迭代服务以进行指定的特征发现
        for service in peripheral.services! {
            peripheral.discoverCharacteristics([CBUUID.init(string: kTransferCharacteristicUUID)], for: service)
        }
    }
    
    // MARK: - 指定特征被发现
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            print("\(Date.init()) 外围设备服务特征发现错误 \(error?.localizedDescription ?? "")")
            return
        }
        print("\(Date.init()) 6外围设备特征被发现了 \(service)")
        
        // MARK: - 发现特征后也可以在这对特征进行写入调用peripheral.write...方法
        
        // 遍历并验证特征然后订阅指定的特征
        let cbuuid = CBUUID.init(string: kTransferCharacteristicUUID)
        for characteristic in service.characteristics! {
            // 如果服务特征是我们想要的就订阅
            if characteristic.uuid == cbuuid {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // MARK: - 外围设备特征被订阅/取消订阅
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            print("\(Date.init()) 外围设备被订阅错误 \(error?.localizedDescription ?? "")")
            return
        }
        
        if characteristic.uuid != CBUUID.init(string: kTransferCharacteristicUUID) {
            return
        }
        
        if characteristic.isNotifying {
            print("\(Date.init()) 特征被中心设备订阅")
        } else {
            print("\(Date.init()) 特征被中心设备取消订阅并断开连接")
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - 外围设备开始发送数据会调用这个方法通知委托来检索characteristic为特征值
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            print("\(Date.init()) 外围设备发送数据错误 \(error?.localizedDescription ?? "")")
            return
        }
        
        let stringFromData = NSString.init(data: characteristic.value!, encoding: String.Encoding.utf8.rawValue)
        print("\(Date.init()) 收到外围设备管理器更新发送的数据 \(stringFromData ?? "")")
        
        if stringFromData == "EOM" {
            // 通知委托数据传输完成
            delegate?.didTransferData(data: data)
            // 传输完成取消订阅以及连接
            peripheral.setNotifyValue(false, for: characteristic)
            centralManager.cancelPeripheralConnection(peripheral)
        } else {
            data.append(characteristic.value!)
        }
    }
    
}
