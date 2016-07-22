//
//  FFTHelper.swift
//  AcousticCommunicateTest
//
//  Created by 小端 みより on 2016/07/22.
//  Copyright © 2016年 小端 みより. All rights reserved.
//

import Accelerate


class FFTCalculator {
    
    typealias Buffer = UnsafeMutablePointer<Float>

    private var mFFTSize: Int
    private var mWindowBuffer: Buffer
    private var mRealBuffer: Buffer
    private var mImaginaryBuffer: Buffer
    private var mSplitComplex: DSPSplitComplex
    private var mOutputSize: Int
    private var mOutputBuffer: Buffer
    private var mFFTSetup: FFTSetup
    
    
    var fftSize: Int {
        get {
            return mFFTSize
        }
    }
    
    var outputSize: Int {
        get {
            return mOutputSize
        }
    }
    
    var output: UnsafePointer<Float> {
        get {
            return UnsafePointer<Float>(mOutputBuffer)
        }
    }
    
    
    
    init(fftSize: Int) {
        mFFTSize = fftSize
        
        mWindowBuffer = Buffer.alloc(fftSize)
        vDSP_hann_window(mWindowBuffer, vDSP_Length(fftSize), 0)

        mRealBuffer = Buffer.alloc(fftSize)
        mImaginaryBuffer = Buffer.alloc(fftSize)
        mSplitComplex = DSPSplitComplex(realp: mRealBuffer, imagp: mImaginaryBuffer)
        
        mOutputSize = fftSize / 2;
        mOutputBuffer = Buffer.alloc(mOutputSize)
        
        let log2n = vDSP_Length(log2(Float(fftSize)))
        mFFTSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    deinit {
        vDSP_destroy_fftsetup(mFFTSetup)
        
        mOutputBuffer.dealloc(mOutputSize)

        mRealBuffer.dealloc(mFFTSize)
        mImaginaryBuffer.dealloc(mFFTSize)
        
        mWindowBuffer.dealloc(mFFTSize)
    }
 
    func calculate(src: Buffer) {
        vDSP_vmul(src, 1, mWindowBuffer, 1, mRealBuffer, 1, vDSP_Length(mFFTSize))
        
        vDSP_ctoz(UnsafePointer<DSPComplex>(mRealBuffer), 2, &mSplitComplex, 1, vDSP_Length(mOutputSize)) // ???
        
        let log2n = vDSP_Length(log2(Float(fftSize)))
        vDSP_fft_zrip(mFFTSetup, &mSplitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        var scale = 1 / Float(mOutputSize);
        vDSP_vsmul(mRealBuffer, 1, &scale, mRealBuffer, 1, vDSP_Length(mOutputSize))
        vDSP_vsmul(mImaginaryBuffer, 1, &scale, mImaginaryBuffer, 1, vDSP_Length(mOutputSize))
        
        vDSP_zvabs(&mSplitComplex, 1, mOutputBuffer, 1, vDSP_Length(mOutputSize))
    }
    
}