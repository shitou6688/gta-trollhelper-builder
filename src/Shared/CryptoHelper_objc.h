// ============================================================
// CryptoHelper — TrollStore.tar.enc AES-256-CBC 解密模块 (ObjC)
// 用于 PersistenceHelper / trollstorehelper (root helper)
// 加密脚本: encrypt_trollstore.py
// 密钥与 CryptoHelper.swift / download_trollstore.php 一致
// ============================================================

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>

// AES-256 密钥（必须和 encrypt_trollstore.py / CryptoHelper.swift 一致）
static NSData* _trollStoreAESKey(void)
{
    static NSData *key = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        key = [@"jumo-tsx-2024-shitou6688-trolls!" dataUsingEncoding:NSUTF8StringEncoding];
    });
    return key;
}

/// 解密 .tar.enc 文件到内存，返回解密后的 tar Data
/// - Parameter encPath: TrollStore.tar.enc 的文件路径
/// - Returns: 解密后的 tar Data，失败返回 nil
static NSData* decryptTarEnc(NSString *encPath)
{
    // 1. 读取加密文件
    NSData *encData = [NSData dataWithContentsOfFile:encPath];
    if (!encData || encData.length < 32) {
        NSLog(@"[CryptoHelper] enc file invalid or too small: %lu bytes", (unsigned long)encData.length);
        return nil;
    }

    // 2. 提取 IV（前 16 字节）和密文
    NSData *ivData = [encData subdataWithRange:NSMakeRange(0, 16)];
    NSData *cipherData = [encData subdataWithRange:NSMakeRange(16, encData.length - 16)];

    // 3. 准备解密缓冲区
    NSData *keyData = _trollStoreAESKey();
    size_t bufferSize = cipherData.length + kCCBlockSizeAES128;
    NSMutableData *buffer = [NSMutableData dataWithLength:bufferSize];
    size_t decryptedLen = 0;

    // 4. AES-256-CBC 解密
    CCCryptorStatus status = CCCrypt(
        kCCDecrypt,
        kCCAlgorithmAES128,
        kCCOptionPKCS7Padding,
        keyData.bytes, kCCKeySizeAES256,
        ivData.bytes,
        cipherData.bytes, cipherData.length,
        buffer.mutableBytes, bufferSize,
        &decryptedLen
    );

    if (status != kCCSuccess) {
        NSLog(@"[CryptoHelper] AES decrypt failed: %d", status);
        return nil;
    }

    // 5. 截取有效数据
    buffer.length = decryptedLen;

    // 6. 简单验证：检查 tar magic "ustar" 在偏移 257
    if (buffer.length > 262) {
        const char *magic = (const char *)buffer.bytes + 257;
        if (memcmp(magic, "ustar", 5) == 0) {
            NSLog(@"[CryptoHelper] Decrypt OK, tar verified (%lu bytes)", (unsigned long)buffer.length);
            return buffer;
        }
    }

    // 即使没有 ustar magic 也返回（可能是非标准 tar）
    NSLog(@"[CryptoHelper] Decrypt OK but no ustar magic (%lu bytes)", (unsigned long)buffer.length);
    return buffer;
}

/// 解密 .tar.enc 并写到临时 .tar 文件
/// - Parameter encPath: .tar.enc 路径
/// - Returns: 临时 .tar 文件路径，失败返回 nil
static NSString* decryptTarEncToTemp(NSString *encPath)
{
    NSData *tarData = decryptTarEnc(encPath);
    if (!tarData) return nil;

    NSString *tmpTarPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.tar", [NSUUID UUID].UUIDString]];

    NSError *writeErr = nil;
    if (![tarData writeToFile:tmpTarPath options:NSDataWritingAtomic error:&writeErr]) {
        NSLog(@"[CryptoHelper] Failed to write temp tar: %@", writeErr);
        return nil;
    }

    NSLog(@"[CryptoHelper] Temp tar written to: %@", tmpTarPath);
    return tmpTarPath;
}
