import Foundation
import AVFoundation

/// 音頻服務類，負責處理 PowerNap 應用程序中的所有音頻播放功能
class AudioService: NSObject, ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    
    @Published var isPlaying = false
    @Published var volume: Float = 0.5
    
    /// 播放指定的音頻文件
    /// - Parameter fileName: 音頻文件名
    /// - Parameter fileExtension: 音頻文件擴展名（默認為mp3）
    /// - Returns: 是否成功開始播放
    func playSound(fileName: String, fileExtension: String = "mp3") -> Bool {
        // 停止正在播放的音頻
        stopSound()
        
        guard let path = Bundle.main.path(forResource: fileName, ofType: fileExtension) else {
            print("找不到音頻文件: \(fileName).\(fileExtension)")
            return false
        }
        
        let url = URL(fileURLWithPath: path)
        
        do {
            // 初始化音頻播放器
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
            
            // 開始播放
            guard let player = audioPlayer, player.play() else {
                print("無法播放音頻")
                return false
            }
            
            isPlaying = true
            return true
        } catch {
            print("播放音頻時出錯: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 停止當前正在播放的音頻
    func stopSound() {
        if let player = audioPlayer, player.isPlaying {
            player.stop()
            isPlaying = false
        }
    }
    
    /// 暫停當前正在播放的音頻
    func pauseSound() {
        if let player = audioPlayer, player.isPlaying {
            player.pause()
            isPlaying = false
        }
    }
    
    /// 繼續播放暫停的音頻
    func resumeSound() -> Bool {
        if let player = audioPlayer, !player.isPlaying {
            if player.play() {
                isPlaying = true
                return true
            }
        }
        return false
    }
    
    /// 設置音量
    /// - Parameter newVolume: 新的音量值（0.0 至 1.0）
    func setVolume(_ newVolume: Float) {
        volume = min(max(newVolume, 0.0), 1.0)
        audioPlayer?.volume = volume
    }
    
    /// 設置循環播放
    /// - Parameter shouldLoop: 是否循環播放
    func setLooping(_ shouldLoop: Bool) {
        audioPlayer?.numberOfLoops = shouldLoop ? -1 : 0
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            DispatchQueue.main.async {
                self.isPlaying = false
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            print("音頻解碼錯誤: \(error.localizedDescription)")
        }
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
} 