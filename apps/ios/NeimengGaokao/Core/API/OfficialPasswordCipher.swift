import CommonCrypto
import Foundation

enum OfficialPasswordCipher {
  static func encrypt(_ plaintext: String, key: String = "0765E81FBE62ACAE") throws -> String {
    guard let keyData = key.data(using: .utf8),
          let inputData = plaintext.data(using: .utf8)
    else {
      throw CipherError.invalidInput
    }

    let outputLength = inputData.count + kCCBlockSizeAES128
    var output = Data(count: outputLength)
    var bytesEncrypted = 0

    let status = output.withUnsafeMutableBytes { outputBuffer in
      inputData.withUnsafeBytes { inputBuffer in
        keyData.withUnsafeBytes { keyBuffer in
          CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
            keyBuffer.baseAddress,
            keyData.count,
            nil,
            inputBuffer.baseAddress,
            inputData.count,
            outputBuffer.baseAddress,
            outputLength,
            &bytesEncrypted
          )
        }
      }
    }

    guard status == kCCSuccess else {
      throw CipherError.encryptionFailed(status)
    }

    output.removeSubrange(bytesEncrypted..<output.count)
    return output.base64EncodedString()
  }

  enum CipherError: Error {
    case invalidInput
    case encryptionFailed(CCCryptorStatus)
  }
}

