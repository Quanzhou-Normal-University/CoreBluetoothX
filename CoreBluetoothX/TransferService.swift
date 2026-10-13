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
	
	var dataToSend: NSData?
	var sendDataIndex: Int?
    // MARK: - 外围设备管理器
    var peripheralManager: CBPeripheralManager!
    // MARK: - 持有服务特征
    var transferCharacteristic: CBMutableCharacteristic!
    
    weak var delegate: TransferServiceDelegate?
    
    init(delegate: TransferServiceDelegate?) {
        super.init()
        peripheralManager = CBPeripheralManager.init(delegate: self, queue: nil)
        self.delegate = delegate
    }
    
    // MARK: - 让外围设备管理器发布广播
    func startAdvertising() {
        let cbuuidService = CBUUID.init(string: kTransferServiceUUID)
        let services = [cbuuidService]
        // CBAdvertisementDataServiceUUIDsKey表示广播服务的键
        let advertisingDict = Dictionary.init(dictionaryLiteral: (CBAdvertisementDataServiceUUIDsKey, services))
        peripheralManager.startAdvertising(advertisingDict)
        print("\(Date.init()) 3.外围设备管理器 开始广播")
    }
    
    // MARK: - 让外围设备管理器停止广播
    func stopAdvertising() {
        print("\(Date.init()) 外围设备管理器 停止广播")
        peripheralManager.stopAdvertising()
    }
	
	// MARK: - 创建服务私有方法
	private func setupServices() {
		let cbuuidCharacteristic = CBUUID.init(string: kTransferCharacteristicUUID)
		transferCharacteristic = CBMutableCharacteristic.init(type: cbuuidCharacteristic, properties: .notify, value: nil, permissions: .readable)
		// value设为nil确保该值被动态处理并且在外围设备管理器接收到读写请求时会被请求否则该值将被缓存并视为只读
		
		// 创建可变服务并关联特征
		let transferService = CBMutableService.init(type: CBUUID.init(string: kTransferServiceUUID), primary: true)
		transferService.characteristics = [transferCharacteristic]
		
		// 发布服务将添加服务到外围设备数据库中且无法更改
		peripheralManager.add(transferService)
	}
	
	// MARK: - 卸载服务私有方法
	private func teardownServices() {
		peripheralManager.removeAllServices()
	}
}

extension TransferService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("\(Date.init()) 1.外围设备管理器 蓝牙已开启开始配置服务")
            
            setupServices()
            delegate?.didPowerOn()
        case .poweredOff:
            print("\(Date.init()) 外围设备管理器 蓝牙已关闭")
            if peripheralManager.isAdvertising {
                stopAdvertising()
            }
            teardownServices()
            delegate?.didPowerOff()
        default:
            print("\(Date.init()) 外围设备管理器 蓝牙已\(peripheral.state)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        print("\(Date.init()) 2.外围设备 添加了服务 \(service)")
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        print("\(Date.init()) 4.外围设备管理器 外围设备开始广播事件")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("外围设备管理器 didReceiveRead")
    }
    
    // MARK: - 远程设备连接并订阅了一个或多个特征值
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("\(Date.init()) 5.外围设备管理器 远程设备连接并订阅了一个或多个特征值 开始像远程设备发送数据")
        // 被订阅了就开始发送数据
        dataToSend = delegate?.getDataToSend()
        sendDataIndex = 0
        sendData()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("\(Date.init()) 外围设备管理器 远程设备取消订阅特征值")
    }
    
    // MARK: - 队列就绪发送数据
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
		print("\(Date.init()) 外围设备管理器 队列就绪继续发送剩余数据")
        sendData()
    }
    
	// MARK: - 发送具体MTU
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
        
        let MTU = 20
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
            // 外围设备管理器将值更新到连接的中心设备上如果成功返回true 如果底层队列满了返回false 等到队列就绪时继续发送剩余数据
            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)
            if !didSend {
                return
            }
            
            print("\(Date.init()) 外围设备管理器 已经更新了特征值 \(String.init(data: chunk, encoding: .utf8) ?? "")")
            
            sendDataIndex! += amountToSend
            if sendDataIndex! >= dataToSend!.length {
                sendEOM()
                return
            }
        }
    }
}
