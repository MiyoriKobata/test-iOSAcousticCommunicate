//
//  ViewController.swift
//  AcousticCommunicateTest
//
//  Created by 小端 みより on 2016/07/15.
//  Copyright © 2016年 小端 みより. All rights reserved.
//

import UIKit
import AudioToolbox
import AudioUnit
import AVFoundation


@objc class ViewController: UIViewController {

    let SAMPLE_RATE = 44100.0;
    let FFT_SIZE = 128;
    let DRAW_INTERVAL = 0.03
    
    
    @IBOutlet weak var mFrequenctyTextField: UITextField!
    @IBOutlet weak var mPlayButton: UIButton!
    @IBOutlet weak var mCaptureButton: UIButton!
    @IBOutlet weak var mFFTSwitch: UISwitch!
    
    var mWaveGraph: WaveGraph?
    var mDrawTimer: NSTimer?
    var mFFTCalculator: FFTCalculator?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // init and add WaveGraph
        let w = view.bounds.width
        let h = view.bounds.height
        mWaveGraph = WaveGraph(frame: CGRect(x: 0.0, y: 50.0, width: w, height: h - 50.0))
        mWaveGraph!.setup(FFT_SIZE)

        view.addSubview(mWaveGraph!)
        
        // init FFTCalculator
        mFFTCalculator = FFTCalculator(fftSize: FFT_SIZE)
        
        mFrequenctyTextField.text = String(mFrequency)
        mPlayButton.setTitle("Play", forState: UIControlState.Normal)
        mCaptureButton.setTitle("Capture", forState: UIControlState.Normal)
        
        initPlayUnit()
        initCaptureUnit()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        // Set category and activate audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredIOBufferDuration(NSTimeInterval(0.005))
        } catch {
            print("AVAudioSession setPreferredIOBufferDuration failed")
            return
        }

        do {
            try session.setPreferredSampleRate(SAMPLE_RATE)
        } catch {
            print("AVAudioSession setPreferredSampleRate failed")
            return
        }
        
        print("setup audio session complete")
    }
    
    func drawWaveGraph(timer: NSTimer) {
        mWaveGraph!.setNeedsDisplay()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        view.endEditing(true)
    }
    
    @IBAction func fftSwitchValueChanged(sender: AnyObject) {
        if mFFTSwitch.on {
            mWaveGraph!.scaleX = 2
            mWaveGraph!.scaleY = 1
            mWaveGraph!.offsetY = 1
        } else {
            mWaveGraph!.scaleX = 1
            mWaveGraph!.scaleY = 0.5
            mWaveGraph!.offsetY = 0.5
        }
    }
    
    
    // -- implementations for playing audio --
    
    var mPlayUnit: AudioUnit = nil
    var mPlaying = false
    var mFrequency = 440.0
    var mPhase = 0.0
    
    private func initPlayUnit() {
        // Instantiate audio unit
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                    componentSubType: kAudioUnitSubType_RemoteIO,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0,
                                                    componentFlagsMask: 0)
        let component = AudioComponentFindNext(nil, &description)
        
        var status = AudioComponentInstanceNew(component, &mPlayUnit);
        if status != noErr {
            print("AudioComponentInstanceNew failed: \(status)");
            return
        }
        
        // Setup audio render callback
        let callback: AURenderCallback = {
            (inRefCon: UnsafeMutablePointer<Void>,
            ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
            inimeStamp: UnsafePointer<AudioTimeStamp>,
            inBusNumber: UInt32,
            inNumberFrames: UInt32,
            ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus in
            
            let viewController = unsafeBitCast(inRefCon, ViewController.self)
            let audioBufferList = UnsafeMutableAudioBufferListPointer(ioData)
            let buffer = unsafeBitCast(audioBufferList[0].mData, UnsafeMutablePointer<Float>.self)
            
            return viewController.renderPlayBuffer(buffer, numFrames: Int(inNumberFrames))
        }
        let selfPointer = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        var callbackStruct = AURenderCallbackStruct(inputProc: callback, inputProcRefCon: selfPointer)
        
        status = AudioUnitSetProperty(mPlayUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input,
                                      0,
                                      &callbackStruct,
                                      UInt32(sizeof(AURenderCallbackStruct)))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_SetRenderCallback kAudioUnitScope_Input failed: \(status)")
            return
        }
        
        // Set audio unit property
        let formatFlags = AudioFormatFlags(kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked |
            kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved)
        let frameSize = UInt32(sizeof(Float));
        var formatDescription = AudioStreamBasicDescription(mSampleRate: SAMPLE_RATE,
                                                            mFormatID: kAudioFormatLinearPCM,
                                                            mFormatFlags: formatFlags,
                                                            mBytesPerPacket: frameSize,
                                                            mFramesPerPacket: 1,
                                                            mBytesPerFrame: frameSize,
                                                            mChannelsPerFrame: 1,
                                                            mBitsPerChannel: frameSize * 8,
                                                            mReserved: 0)
        
        status = AudioUnitSetProperty(mPlayUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &formatDescription,
                                      UInt32(sizeof(AudioStreamBasicDescription)))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_StreamFormat kAudioUnitScope_Input failed: \(status)");
            return
        }
        
        // Initialize audio unit
        status = AudioUnitInitialize(mPlayUnit)
        if status != noErr {
            print("AudioUnitInitialize failed: \(status)");
            return
        }
        
        print("initializing play audio unit complete!")
    }

    private func renderPlayBuffer(buffer: UnsafeMutablePointer<Float>, numFrames: Int) -> OSStatus {
        var phase = mPhase
        let delta = mFrequency * M_PI * 2 / SAMPLE_RATE
        
        // Iterate and write samples
        for i in 0 ..< numFrames {
            buffer[i] = Float(sin(phase))
            phase += delta
        }
        
        mPhase = fmod(phase, M_PI * 2)
        
        // Send to WaveGraph
        if mFFTSwitch.on {
            if numFrames >= mFFTCalculator?.fftSize {
                mFFTCalculator!.calculate(buffer)
                mWaveGraph!.writeBuffer(mFFTCalculator!.output, length: mFFTCalculator!.outputSize)
//                mWaveGraph!.scaleX = 2
            }
        } else {
            mWaveGraph!.writeBuffer(buffer, length: numFrames)
        }
        
        return noErr
    }
    
    @IBAction func playButtonTouchDown(sender: AnyObject) {
        if !mPlaying {
            if let frequency = Double(mFrequenctyTextField.text!) {
                mFrequency = frequency
            }
            startPlay()
            
            mDrawTimer = NSTimer.scheduledTimerWithTimeInterval(DRAW_INTERVAL,
                                                                target: self,
                                                                selector: #selector(drawWaveGraph(_:)),
                                                                userInfo: nil,
                                                                repeats: true)
        } else {
            stopPlay()
            
            mDrawTimer!.invalidate()
            mDrawTimer = nil
        }
    }
    
    private func startPlay() {
        // Set category and activate audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(AVAudioSessionCategoryPlayback)
        } catch {
            print("AVAudioSession setCategory AVAudioSessionCategoryPlayback failed")
            return
        }
        
        do {
            try session.setActive(true)
        } catch {
            print("AVAudioSession setActivate true failed")
            return
        }

        mPhase = 0.0
        
        // Start audio unit
        let status = AudioOutputUnitStart(mPlayUnit)
        if status != noErr {
            print("AudioOutputUnitStart failed: \(status)")
            return
        }
        
        mPlaying = true
        print("start playing audio!")
        
        mPlayButton.setTitle("Stop", forState: UIControlState.Normal)
        mCaptureButton.enabled = false
    }
    
    private func stopPlay() {
        // Stop audio unit
        let status = AudioOutputUnitStop(mPlayUnit)
        if status == noErr {
            print("stop playing audio!")
        } else {
            print("AudioOutputUnitStop failed: \(status)")
        }
        
        // Deactivate audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false)
        } catch {
            print("AVAudioSession setActivate false failed")
        }
        
        mPlaying = false
        
        mPlayButton.setTitle("Play", forState: UIControlState.Normal)
        mCaptureButton.enabled = true
    }
    
    @IBAction func textFieldEditingChanged(sender: AnyObject) {
        if let frequency = Double(mFrequenctyTextField.text!) {
            mFrequency = frequency
        }
    }
    
    // -- implementations for capturing audio --
    
    var mCaptureUnit: AudioUnit = nil
    var mCapturing = false
    
    private func initCaptureUnit() {
        // Instantiate audio unit
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                    componentSubType: kAudioUnitSubType_RemoteIO,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0,
                                                    componentFlagsMask: 0)
        let component = AudioComponentFindNext(nil, &description)
        
        var status = AudioComponentInstanceNew(component, &mCaptureUnit)
        if status != noErr {
            print("AudioComponentInstanceNew failed: \(status)")
            return
        }
        
        // Set audio input callback
        let callback: AURenderCallback = {
            (inRefCon: UnsafeMutablePointer<Void>,
            ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
            inimeStamp: UnsafePointer<AudioTimeStamp>,
            inBusNumber: UInt32,
            inNumberFrames: UInt32,
            ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus in
            
            // input callback
            let viewController = unsafeBitCast(inRefCon, ViewController.self)
            
            let buffer = UnsafeMutablePointer<Float>.alloc(Int(inNumberFrames))
            let audioBuffer = AudioBuffer(mNumberChannels: 1,
                                          mDataByteSize: UInt32(sizeof(Float)) * inNumberFrames,
                                          mData: buffer)
            var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            
            var status = AudioUnitRender(viewController.mCaptureUnit,
                                         ioActionFlags,
                                         inimeStamp,
                                         inBusNumber,
                                         inNumberFrames,
                                         &audioBufferList)
            if status != noErr {
                print("AudioUnitRender failed: \(status)")
                return status
            }
            
            status = viewController.renderCaptureBuffer(buffer, numFrames: Int(inNumberFrames));
            
            buffer.dealloc(Int(inNumberFrames))
            
            return status;
        }
        let selfPointer = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        var callbackStruct = AURenderCallbackStruct(inputProc: callback, inputProcRefCon: selfPointer)
        
        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioOutputUnitProperty_SetInputCallback,
                                      kAudioUnitScope_Global,
                                      1,
                                      &callbackStruct,
                                      UInt32(sizeof(AudioStreamBasicDescription)))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_SetRenderCallback kAudioUnitScope_Input failed: \(status)")
            return
        }
        
        // Set audio unit properties
        var value: UInt32 = 1;
        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,
                                      1,
                                      &value,
                                      UInt32(sizeof(UInt32)))
        if status != noErr {
            print("AudioUnitSetProperty kAudioOutputUnitProperty_EnableIO kAudioUnitScope_Input failed: \(status)")
            return
        }

        value = 0
        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output,
                                      0,
                                      &value,
                                      UInt32(sizeof(UInt32)))
        if status != noErr {
            print("AudioUnitSetProperty kAudioOutputUnitProperty_EnableIO kAudioUnitScope_Output failed: \(status)")
            return
        }
        
        // Set audio format
        let formatFlags = AudioFormatFlags(kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked |
            kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved)
        let frameSize = UInt32(sizeof(Float));
        var formatDescription = AudioStreamBasicDescription(mSampleRate: SAMPLE_RATE,
                                                            mFormatID: kAudioFormatLinearPCM,
                                                            mFormatFlags: formatFlags,
                                                            mBytesPerPacket: frameSize,
                                                            mFramesPerPacket: 1,
                                                            mBytesPerFrame: frameSize,
                                                            mChannelsPerFrame: 1,
                                                            mBitsPerChannel: frameSize * 8,
                                                            mReserved: 0)

        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      1,
                                      &formatDescription,
                                      UInt32(sizeof(AudioStreamBasicDescription)))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_StreamFormat kAudioUnitScope_Output failed: \(status)")
            return
        }
        
        // Initialize audio unit
        status = AudioUnitInitialize(mCaptureUnit)
        if status != noErr {
            print("AudioUnitInitialize failed: \(status)")
            return
        }

        print("initializing capture audio unit complete!")
    }
    
    private func renderCaptureBuffer(buffer: UnsafeMutablePointer<Float>, numFrames: Int) -> OSStatus {
        // need DC rejection ??
        
        // Send to WaveGraph
        if mFFTSwitch.on {
            if numFrames >= mFFTCalculator?.fftSize {
                mFFTCalculator!.calculate(buffer)
                mWaveGraph!.writeBuffer(mFFTCalculator!.output, length: mFFTCalculator!.outputSize)
            }
        } else {
            mWaveGraph!.writeBuffer(buffer, length: numFrames)
        }
        
        return noErr
    }
    
    @IBAction func captureButtonTouchDown(sender: AnyObject) {
        if !mCapturing {
            startCapture()
            
            mDrawTimer = NSTimer.scheduledTimerWithTimeInterval(DRAW_INTERVAL,
                                                                target: self,
                                                                selector: #selector(drawWaveGraph(_:)),
                                                                userInfo: nil,
                                                                repeats: true)
        } else {
            stopCapture();
            
            mDrawTimer!.invalidate()
            mDrawTimer = nil
        }
    }
    
    private func startCapture() {
        // Set category and activate audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(AVAudioSessionCategoryRecord)
        } catch {
            print("AVAudioSession setCategory AVAudioSessionCategoryRecord failed")
            return
        }
        
        do {
            try session.setActive(true)
        } catch {
            print("AVAudioSession setActivate true failed")
            return
        }
        
        // Start audio unit
        let status = AudioOutputUnitStart(mCaptureUnit)
        if status != noErr {
            print("AudioOutputUnitStart failed: \(status)")
            return
        }
        
        mCapturing = true
        print("start capturing audio!")
        
        mCaptureButton.setTitle("Stop", forState: UIControlState.Normal)
        mPlayButton.enabled = false
    }
    
    private func stopCapture() {
        // Stop audio unit
        let status = AudioOutputUnitStop(mCaptureUnit)
        if status == noErr {
            print("stop capturing audio!")
        } else {
            print("AudioOutputUnitStop failed: \(status)")
        }
        
        // Deactivate audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false)
        } catch {
            print("AVAudioSession setActivate false failed")
        }
        
        mCapturing = false
        
        mCaptureButton.setTitle("Capture", forState: UIControlState.Normal)
        mPlayButton.enabled = true
    }
    
}

