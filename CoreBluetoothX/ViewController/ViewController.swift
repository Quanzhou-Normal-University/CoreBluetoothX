//
//  ViewController.swift
//  CoreBluetoothX
//
//  Created by 杨俊艺 on 2021/11/19.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController {
    @IBOutlet weak var bluetoothStateLabel: UILabel!
    
    // MARK: - 中心设备管理器
    var centralManager: CBCentralManager!
    var isBluetoothPoweredOn = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 中心设备初始化即刻开始发送事件
        centralManager = CBCentralManager.init(delegate: self, queue: nil)
    }
    
    // MARK: - 蓝牙开启了才能跳转
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == kCentralRoleSegue || identifier == kPeripheralRoleSegue {
            if !isBluetoothPoweredOn {
                showAlertForSettings()
            }
            return isBluetoothPoweredOn
        } else {
            return true
        }
    }

}

// MARK: - 中心设备管理器委托回调
extension ViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            isBluetoothPoweredOn = true
            bluetoothStateLabel.text = "蓝牙已打开"
            bluetoothStateLabel.textColor = .green
        case .poweredOff:
            isBluetoothPoweredOn = false
            bluetoothStateLabel.text = "蓝牙已关闭"
            bluetoothStateLabel.textColor = .red
        default:
            break
        }
    }
}

// MARK: - 提示工具
extension ViewController {
    func showAlertForSettings() {
        let okAction = UIAlertAction.init(title: "OK", style: .default, handler: nil)
        let openSettings = UIAlertAction.init(title: "设置", style: .cancel) { action in
            let url = URL.init(string: UIApplication.openSettingsURLString)
            UIApplication.shared.open(url!, options: [:], completionHandler: nil)
        }
        let alertController = UIAlertController.init(title: "蓝牙连接", message: "请到设置打开蓝牙后进行操作", preferredStyle: .alert)
            alertController.addAction(okAction)
            alertController.addAction(openSettings)
        
        present(alertController, animated: true, completion: nil)
    }
}
