//
//  TransferService.swift
//  CoreBluetoothX
//
//  Created by 杨俊艺 on 2021/11/20.
//

import CoreBluetooth

protocol TransferServiceDelegate: NSObjectProtocol {
    func didPowerOn()
    func didPowerOff()
    func getDataToSend() -> NSData
}

// MARK: - 将外围设备视图控制器蓝牙交互细节抽到这个类中然后处理完蓝牙交互通过委托回调出去
class TransferService: NSObject {
    // MARK: - 外围设备管理器
    var peripheralManager: CBPeripheralManager!
    // MARK: - 服务特征
    var transferCharacteristic: CBMutableCharacteristic!
    var dataToSend: NSData?
    var sendDataIndex: Int?
    
    weak var delegate: TransferServiceDelegate?
    
    init(delegate: TransferServiceDelegate?) {
        super.init()
        
        peripheralManager = CBPeripheralManager.init(delegate: self, queue: nil)
        self.delegate = delegate
    }
    
    // MARK: - 创建服务
    private func setupServices() {
        let cbuuidCharacteristic = CBUUID.init(string: kTransferCharacteristicUUID)
        transferCharacteristic = CBMutableCharacteristic.init(type: cbuuidCharacteristic, properties: .notify, value: nil, permissions: .readable)
        // value设为nil确保该值被动态处理并且在外围设备管理器接收到读写请求时会被请请求否则该值将被缓存并视为只读
        
        
        // 创建可变服务并关联特征
        let cbuuidService = CBUUID.init(string: kTransferServiceUUID)
        let transferService = CBMutableService.init(type: cbuuidService, primary: true)
            transferService.characteristics = [transferCharacteristic]
        
        // 发布服务将添加服务到外围设备数据库中且无法更改
        peripheralManager.add(transferService)
        print("\(Date.init()) 外围设备管理器发布服务成功")
    }
    
    // MARK: - 卸载服务
    private func teardownServices() {
        peripheralManager.removeAllServices()
    }
    
    // MARK: - 让外围设备管理器发布广播
    func startAdvertising() {
        let cbuuidService = CBUUID.init(string: kTransferServiceUUID)
        let services = [cbuuidService]
        // CBAdvertisementDataServiceUUIDsKey表示广播服务的键
        let advertisingDict = Dictionary.init(dictionaryLiteral: (CBAdvertisementDataServiceUUIDsKey, services))
        peripheralManager.startAdvertising(advertisingDict)
        print("\(Date.init()) 外围设备管理器开始广播")
    }
    
    // MARK: - 让外围设备管理器停止广播
    func stopAdvertising() {
        print("\(Date.init()) 外围设备管理器停止广播")
        
        peripheralManager.stopAdvertising()
    }
}

extension TransferService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("\(Date.init()) 外围设备管理器蓝牙已开启并发布服务")
            
            setupServices()
            delegate?.didPowerOn()
        case .poweredOff:
            print("\(Date.init()) 外围设备管理器蓝牙已关闭")
            
            if peripheralManager.isAdvertising {
                stopAdvertising()
            }
            teardownServices()
            delegate?.didPowerOff()
        default:
            print("\(Date.init()) 外围设备管理器蓝牙已\(peripheral.state)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        print("\(Date.init()) 外围设备添加了服务 \(service)")
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        print("\(Date.init()) 外围设备管理器的委托知道了外围设备开始广播")
    }
    
    // MARK: - 远程设备连接并订阅了一个或多个特征值
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("\(Date.init()) 远程设备连接并订阅了一个或多个特征值")
        // 被订阅了就开始发送数据
        dataToSend = delegate?.getDataToSend()
        sendDataIndex = 0
        sendData()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("\(Date.init()) 远程设备取消订阅特征值")
    }
    
    // MARK: - 队列就绪发送数据
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        sendData()
    }
    
    func sendData() {
        struct eom {
            static var pending = false
        }
        
        // MARK: - 发送数据结束标记并返回有没有发送成功
        @discardableResult func sendEOM() -> Bool {
            eom.pending = true
            
            let data = ("EOM" as NSString).data(using: String.Encoding.utf8.rawValue)
            if peripheralManager.updateValue(data!, for: transferCharacteristic, onSubscribedCentrals: nil) {
                eom.pending = false
            }
            return !eom.pending
        }
        
        
        let MTU = 200
        if eom.pending {
            if sendEOM() {
                return
            }
        }
        
        if sendDataIndex! >= dataToSend!.length {
            return
        }
        
        var didSend = true
        while didSend {
            // 指定要发送数据的长度限制
            // 如果剩余数据大于最大传输单元MTU就指定为MTU
            var amountToSend = dataToSend!.length - sendDataIndex!
            if amountToSend > MTU {
                amountToSend = MTU
            }
            
            let chunk = Data.init(bytes: dataToSend!.bytes + sendDataIndex!, count: amountToSend)
            // 外围设备管理器更新特征值成功返回true
            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)
            if !didSend {
                return
            }
            
            print("\(Date.init()) 外围设备管理器已经更新了特征值 \(String.init(data: chunk, encoding: .utf8) ?? "")")
            
            sendDataIndex! += amountToSend
            if sendDataIndex! >= dataToSend!.length {
                sendEOM()
                return
            }
        }
        
    }
    
}
