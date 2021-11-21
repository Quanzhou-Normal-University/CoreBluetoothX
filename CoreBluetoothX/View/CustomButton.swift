//
//  CustomButton.swift
//  CoreBluetoothX
//
//  Created by 杨俊艺 on 2021/11/19.
//

import UIKit

@IBDesignable
class CustomButton: UIButton {
    @IBInspectable var cornerRadius: CGFloat = 0 {
        didSet {
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = cornerRadius > 0
        }
    }
    
    @IBInspectable var borderWidth: CGFloat = 0 {
        didSet {
            layer.borderWidth = borderWidth
        }
    }
    
    @IBInspectable var borderColor: UIColor? {
        didSet {
            layer.borderColor = borderColor?.cgColor
        }
    }
}

extension UIView {
    func rotete(fromValue: CGFloat, toValue: CGFloat, duration: CFTimeInterval = 1.0, completionDelegate: AnyObject? = nil) {
        let rotateAnimation = CABasicAnimation.init(keyPath: "transform.rotation")
        rotateAnimation.fromValue = fromValue
        rotateAnimation.toValue = toValue
        rotateAnimation.duration = duration
        
        if let completionDelegate = completionDelegate {
            rotateAnimation.delegate = completionDelegate as? CAAnimationDelegate
        }
        layer.add(rotateAnimation, forKey: nil)
    }
}
