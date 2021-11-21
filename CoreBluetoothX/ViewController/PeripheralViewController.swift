//
//  PeripheralViewController.swift
//  CoreBluetoothX
//
//  Created by 杨俊艺 on 2021/11/20.
//

import UIKit
import CoreBluetooth

class PeripheralViewController: UIViewController, UITextViewDelegate {
    @IBOutlet weak var advertiseSwitch: UISwitch!
    @IBOutlet weak var textView: UITextView!
    
    var transferService: TransferService!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        transferService = TransferService.init(delegate: self)
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        let rightButton = UIBarButtonItem(title: "Done", style: UIBarButtonItem.Style.done, target: self, action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
    }
    
    // MARK: - 文本改变了就停止广播
    func textViewDidChange(_ textView: UITextView) {
        if advertiseSwitch.isOn {
            advertiseSwitch.setOn(false, animated: true)
            transferService.stopAdvertising()
        }
    }
    
    @IBAction func advertiseSwitchDidChange(_ sender: Any) {
        if advertiseSwitch.isOn {
            transferService.startAdvertising()
        } else {
            transferService.stopAdvertising()
        }
    }
    
    @objc func dismissKeyboard() {
        textView.resignFirstResponder()
        navigationItem.rightBarButtonItem = nil
    }
    
}

extension PeripheralViewController: TransferServiceDelegate {
    func didPowerOn() {
        
    }
    
    func didPowerOff() {
        advertiseSwitch.setOn(false, animated: true)
    }
    
    func getDataToSend() -> NSData {
        return textView.text.data(using: .utf8)! as NSData
    }
    
}
