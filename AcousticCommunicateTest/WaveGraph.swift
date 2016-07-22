//
//  WaveDraw.swift
//  AcousticCommunicateTest
//
//  Created by 小端 みより on 2016/07/21.
//  Copyright © 2016年 小端 みより. All rights reserved.
//

import UIKit

class WaveGraph: UIView {
    var scaleX = 1.0
    var scaleY = 0.5
    var offsetY = 0.5
    
    
    private var mBuffer: UnsafeMutablePointer<Float> = nil
    private var mBufferSize = 0;
    private var mWroteSize = 0
    
    
    private class Syncer {
        private let mObj: AnyObject
        
        init(_ obj: AnyObject) {
            mObj = obj
            objc_sync_enter(obj)
        }
        
        deinit {
            objc_sync_exit(mObj)
        }
    }
    
    
    deinit {
        if mBuffer != nil {
            mBuffer.dealloc(mBufferSize)
            mBuffer = nil
        }
    }
    
    override func drawRect(rect: CGRect) {
        UIColor.blackColor().setFill()
        
        let rect = UIBezierPath(rect: CGRectMake(0, 0, bounds.width, bounds.height))
        rect.lineWidth = 0
        rect.fill()

        let _ = Syncer(self)
        
        guard (mBuffer != nil) && (mWroteSize > 0) else {
            return
        }
        
//        UIColor(red: CGFloat(arc4random()) / CGFloat(UInt32.max),
//                green: CGFloat(arc4random()) / CGFloat(UInt32.max),
//                blue: CGFloat(arc4random()) / CGFloat(UInt32.max),
//                alpha: 1).setStroke()
        UIColor.greenColor().setStroke()

        let line = UIBezierPath();
        line.lineWidth = 1

        var numPoints = 0
        var point = CGPoint()
        for index in 0 ..< mWroteSize {
            let value = mBuffer[index]
            
            if isnan(value) {
                print("nan: \(index)")
                continue;
            }

            point.x = CGFloat(Double(index) * scaleX / Double(mBufferSize)) * bounds.width
            point.y = CGFloat(Double(-value) * scaleY + offsetY) * bounds.height

            if numPoints == 0 {
                line.moveToPoint(point)
            } else {
                line.addLineToPoint(point)
            }
            
            numPoints += 1
        }
        
        if numPoints > 0 {
            line.stroke()
        }
    }
    
    func setup(bufferSize: Int) {
        let _ = Syncer(self)
        
        if mBuffer != nil {
            mBuffer.dealloc(mBufferSize)
        }
        
        mBuffer = UnsafeMutablePointer<Float>.alloc(bufferSize)
        mBufferSize = bufferSize
    }
    
    func clearBuffer() {
        mWroteSize = 0
    }
    
    func writeBuffer(src: UnsafePointer<Float>, length: Int) {
        guard mBuffer != nil else {
            print("buffer is not allocated")
            return
        }
        
        let _ = Syncer(self)
        
        mWroteSize = min(length, mBufferSize)
        memcpy(mBuffer, src, sizeof(Float) * mWroteSize)
    }
    
}
