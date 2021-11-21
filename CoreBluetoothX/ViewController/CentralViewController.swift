//
//  CentralViewController.swift
//  CoreBluetoothX
//
//  Created by 杨俊艺 on 2021/11/19.
//

import UIKit
import CoreBluetooth

class CentralViewController: UIViewController {
    @IBOutlet weak var scanButton: CustomButton!
    @IBOutlet weak var textView: UITextView!
    
    // MARK: - 蓝牙传输服务扫描工具
    var transferServiceScanner: TransferServiceScanner!
    // MARK: - 蓝牙传输服务扫描工具是否在扫描中
    var isScanning = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        transferServiceScanner = TransferServiceScanner.init(delegate: self)
    }
    
    // MARK: - 蓝牙传输服务扫描工具开始扫描
    @IBAction func toggleScanning() {
        isScanning ? transferServiceScanner.stopScan() : transferServiceScanner.startScan()
    }
    
}

// MARK: - 蓝牙传输服务扫描工具委托回调
extension CentralViewController: TransferServiceScannerDelegate {
    func didStartScan() {
        if !isScanning {
            isScanning = true
            textView.text = "扫描中"
            scanButton.rotete(fromValue: 0, toValue: .pi * 2, duration: 1, completionDelegate: self)
        }
    }
    
    func didStopScan() {
        isScanning = false
        textView.text = ""
    }
    
    func didTransferData(data: NSData?) {
        print("\(Date.init()) 已经接收到全部数据")
        let stringFromData = NSString(data: data! as Data, encoding: String.Encoding.utf8.rawValue)
        textView.text = stringFromData! as String
    }
    
}

// MARK: - 扫描按钮旋转动画委托回调
extension CentralViewController: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        // 开始扫描将旋转360度旋转结束判断是否还在扫描中如果是接着旋转360度
        if isScanning {
            scanButton.rotete(fromValue: 0, toValue: .pi * 2, duration: 1, completionDelegate: self)
        }
    }
}
