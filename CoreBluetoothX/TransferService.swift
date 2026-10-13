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
    
	// MARK: - 发送数据给订阅了特征的中心设备
    /// 该函数被两个地方调用:
    /// 1. 远程中心设备订阅特征时 didSubscribeTo (首次触发)
    /// 2. 蓝牙发送队列就绪时 peripheralManagerIsReady(toUpdateSubscribers:) (继续发送剩余数据)
    /// 采用分片机制: 将大数据拆成 MTU(20字节) 大小的数据包逐包发送, 最后发送 "EOM" 结束标记
    func sendData() {
        // 使用内嵌静态变量记录 EOM(End Of Message) 是否处于待发送状态
        // 因为 updateValue 可能因队列满而失败, 所以需要记住 EOM 还没发出去, 等队列就绪后重试
        struct eom {
            static var pending = false// 队列是否满了
        }
		
        // MARK: - 发送结束标记 EOM 的辅助方法
        /// EOM 用于告知接收方: 本次数据已经全部发完, 可以组装完整消息了
        /// - Returns: true 表示 EOM 发送成功或已经发送过; false 表示底层队列满了, 需要等待下次队列就绪再重试
        @discardableResult func sendEOM() -> Bool {
            // 先把 pending 标记为 true, 表示现在正尝试发送 EOM
            eom.pending = true
			
            // 将字符串 "EOM" 编码为 UTF-8 Data
            let data = ("EOM" as NSString).data(using: String.Encoding.utf8.rawValue)
            // 通过 updateValue 推送给所有已订阅该特征的中心设备
            // onSubscribedCentrals: nil 表示发给所有订阅者
            if peripheralManager.updateValue(data!, for: transferCharacteristic, onSubscribedCentrals: nil) {
                // 推送成功, 重置 pending 状态
                eom.pending = false
            }
            // 返回是否成功发送
            return !eom.pending
        }
		
        // 蓝牙 BLE 默认 ATT MTU 通常为 23, 减去 3 字节 ATT 头, 剩余 20 字节作为有效载荷
        // 这里固定每次最多发 20 字节, 保证兼容性
        let MTU = 20
		
        // 如果上次 EOM 没发出去(队列满了), 先尝试重发 EOM 重发成功就可以直接返回, 因为这意味着整批数据已经完整送达
        if eom.pending {
            if sendEOM() {
                return
            }
        }
		
        // 边界检查: 如果当前索引已经超过或等于数据总长, 说明数据已经发完直接返回, 不再重复发送 EOM
        if sendDataIndex! >= dataToSend!.length {
            return
        }
		
        // didSend 标记本次 updateValue 是否成功入队
        var didSend = true
        // 循环分片发送, 只要底层队列未满就一直发
        while didSend {
            // 计算本次还能发送多少字节: 总长度 - 已发送索引
            var amountToSend = dataToSend!.length - sendDataIndex!
            // 如果剩余数据超过 MTU, 则本次只发 MTU 字节
            if amountToSend > MTU {
                amountToSend = MTU
            }
			
            // 从 dataToSend 的当前索引位置截取 amountToSend 长度的子数据块
            // dataToSend!.bytes 指向 NSData 内部字节缓冲区的首地址, 加上 sendDataIndex 偏移得到当前分片起始地址
            let chunk = Data.init(bytes: dataToSend!.bytes + sendDataIndex!, count: amountToSend)

            // 调用 Core Bluetooth 的 updateValue 将分片推送到订阅的中心设备
            // 返回 true: 数据已成功放入发送队列
            // 返回 false: 底层队列已满, 需要停止发送, 等待 peripheralManagerIsReady(toUpdateSubscribers:) 回调再继续
            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)
            if !didSend {
                // 队列满了, 退出循环, 保留 sendDataIndex 不变, 下次队列就绪时从当前位置继续
                return
            }
			
            // 发送成功, 打印日志便于调试
            print("\(Date.init()) 外围设备管理器 已经更新了特征值 \(String.init(data: chunk, encoding: .utf8) ?? "")")
			
            // 将索引向前推进本次发送的字节数
            sendDataIndex! += amountToSend
			
            // 如果索引已经到达或超过数据总长度, 说明所有分片都已发完发送 EOM 结束标记然后结束本次发送流程
            if sendDataIndex! >= dataToSend!.length {
                sendEOM()
                return
            }
        }
    }
}
