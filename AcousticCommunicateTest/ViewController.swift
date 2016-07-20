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


class ViewController: UIViewController {

    let SAMPLE_RATE = 44100.0;
    
    
    @IBOutlet weak var mFrequenctyInputField: UITextField!
    @IBOutlet weak var mPlayButton: UIButton!
    @IBOutlet weak var mCaptureButton: UIButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        mFrequenctyInputField.text = String(mFrequency)
        mPlayButton.setTitle("Play", forState: UIControlState.Normal)
        
        initPlayUnit()
        initCaptureUnit()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    // -- implementations for playing audio --
    
    var mPlayUnit: AudioUnit = nil
    var mPlaying = false
    var mFrequency = 440.0
    var mPhase = 0.0
    
    func initPlayUnit() {
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
        
        // Set audio unit property
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: SAMPLE_RATE, channels: 1)
        var streamDescription = audioFormat.streamDescription.memory
        
        status = AudioUnitSetProperty(mPlayUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &streamDescription,
                                      SizeOf32(streamDescription))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_StreamFormat kAudioUnitScope_Input failed: \(status)");
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
            let audioBuffer = audioBufferList[0]
            let buffer = unsafeBitCast(audioBuffer.mData, UnsafeMutablePointer<Float>.self)

            return viewController.playRender(buffer, numberFrames: Int(inNumberFrames))
        }
        let selfPointer = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        var callbackStruct = AURenderCallbackStruct(inputProc: callback, inputProcRefCon: selfPointer)
        
        status = AudioUnitSetProperty(mPlayUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input,
                                      0,
                                      &callbackStruct,
                                      SizeOf32(callbackStruct))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_SetRenderCallback kAudioUnitScope_Input failed: \(status)")
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

    func playRender(buffer: UnsafeMutablePointer<Float>, numberFrames: Int) -> OSStatus {
        var phase: Float = Float(mPhase)
        let delta: Float = Float(mFrequency * M_PI * 2 / SAMPLE_RATE)
        
        // Iterate all samples
        for i in 0 ..< numberFrames {
            buffer[i] = sinf(phase)
            phase += delta
        }
        
        mPhase = fmod(Double(phase), M_PI * 2)
        
        return noErr
    }
    
    @IBAction func playButtonTouchDown(sender: AnyObject) {
        if !mPlaying {
            if let frequency = Double(mFrequenctyInputField.text!) {
                mFrequency = frequency
            }
            
            playAudio()
        } else {
            stopAudio()
        }
    }
    
    func playAudio() {
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
    }
    
    func stopAudio() {
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
    }
    
    
    // -- implementations for capturing audio --
    
    var mCaptureUnit: AudioUnit = nil
    
    func initCaptureUnit() {
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
        
        // Set audio unit properties
        var value: UInt32 = 1;
        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,
                                      1,
                                      &value,
                                      SizeOf32(value))
        if status != noErr {
            print("AudioUnitSetProperty kAudioOutputUnitProperty_EnableIO kAudioUnitScope_Input failed: \(status)")
            return
        }

        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output,
                                      0,
                                      &value,
                                      SizeOf32(value))
        if status != noErr {
            print("AudioUnitSetProperty kAudioOutputUnitProperty_EnableIO kAudioUnitScope_Output failed: \(status)")
            return
        }
        
        var audioStreamDescription = CAStreamBasicDescription(sampleRate: SAMPLE_RATE,
                                                              numChannels: 1,
                                                              pcmf: CAStreamBasicDescription.CommonPCMFormat.Float32,
                                                              isInterleaved: false)
        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      1,
                                      &audioStreamDescription,
                                      SizeOf32(audioStreamDescription))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_StreamFormat kAudioUnitScope_Output failed: \(status)")
            return
        }
        
        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &audioStreamDescription,
                                      SizeOf32(audioStreamDescription))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_StreamFormat kAudioUnitScope_Input failed: \(status)")
            return
        }
        
        var maxFramesPerSlice: UInt32 = 4096
        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global,
                                      0,
                                      &maxFramesPerSlice,
                                      SizeOf32(maxFramesPerSlice))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_MaximumFramesPerSlice kAudioUnitScope_Global failed: \(status)")
            return
        }
        
        var size = SizeOf32(maxFramesPerSlice)
        status = AudioUnitGetProperty(mCaptureUnit,
                                      kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global,
                                      0,
                                      &maxFramesPerSlice,
                                      &size)
        if status != noErr {
            print("AudioUnitGetProperty kAudioUnitProperty_MaximumFramesPerSlice kAudioUnitScope_Global failed: \(status)")
            return;
        }
        
        // Setup audio render callback
        let callback: AURenderCallback = {
            (inRefCon: UnsafeMutablePointer<Void>,
            ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
            inimeStamp: UnsafePointer<AudioTimeStamp>,
            inBusNumber: UInt32,
            inNumberFrames: UInt32,
            ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus in
            
            // Render callback
            
            // todo
            
            return noErr
        }
        let selfPointer = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        var callbackStruct = AURenderCallbackStruct(inputProc: callback, inputProcRefCon: selfPointer)
        
        status = AudioUnitSetProperty(mCaptureUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input,
                                      0,
                                      &callbackStruct,
                                      SizeOf32(callbackStruct))
        if status != noErr {
            print("AudioUnitSetProperty kAudioUnitProperty_SetRenderCallback kAudioUnitScope_Input failed: \(status)")
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
    
    
}

