/*
 * Copyright 2023 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:core';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:network_proxy/network/util/x509/basic_constraints.dart';
import 'package:network_proxy/network/util/x509/x509.dart';
import 'package:path_provider/path_provider.dart';
import 'package:network_proxy/network/util/x509/key_usage.dart' as x509;

import 'file_read.dart';

Future<void> main() async {
  await CertificateManager.getCertificateContext('www.jianshu.com');
  CertificateManager.caCert.tbsCertificateSeqAsString;

  String cer = CertificateManager.get('www.jianshu.com')!;
  var x509certificateFromPem = X509Utils.x509CertificateFromPem(cer);
  print(x509certificateFromPem.plain!);
}

class CertificateManager {
  /// 证书缓存
  static final Map<String, String> _certificateMap = {};

  /// 服务端密钥
  static AsymmetricKeyPair _serverKeyPair = CryptoUtils.generateRSAKeyPair();

  /// ca证书
  static late X509CertificateData _caCert;

  /// ca私钥
  static late RSAPrivateKey _caPriKey;

  /// 是否初始化
  static bool _initialized = false;

  static String? get(String host) {
    return _certificateMap[host];
  }

  static X509CertificateData get caCert => _caCert;

  /// 清除缓存
  static void cleanCache() {
    _certificateMap.clear();
  }

  /// 获取域名自签名证书
  static Future<SecurityContext> getCertificateContext(String host) async {
    var cer = _certificateMap[host];

    if (cer == null) {
      if (!_initialized) {
        await _initCAConfig();
      }
      cer = generate(_caCert, _serverKeyPair.publicKey as RSAPublicKey, _caPriKey, host);
      _certificateMap[host] = cer;
    }

    var rsaPrivateKey = _serverKeyPair.privateKey as RSAPrivateKey;

    return SecurityContext.defaultContext
      ..useCertificateChainBytes(cer.codeUnits)
      ..allowLegacyUnsafeRenegotiation = true
      ..usePrivateKeyBytes(CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(rsaPrivateKey).codeUnits);
  }

  /// 生成证书
  static String generate(X509CertificateData caRoot, RSAPublicKey serverPubKey, RSAPrivateKey caPriKey, String host) {
    //根据CA证书subject来动态生成目标服务器证书的issuer和subject
    Map<String, String> x509Subject = {
      'C': 'CN',
      'ST': 'BJ',
      'L': 'Beijing',
      'O': 'Proxy',
      'OU': 'ProxyPin',
    };

    x509Subject['CN'] = host;

    var csrPem = X509Generate.generateSelfSignedCertificate(caRoot, serverPubKey, caPriKey, 365,
        sans: [host], serialNumber: Random().nextInt(1000000).toString(), subject: x509Subject);
    return csrPem;
  }

  //重新生成根证书
  static Future<void> generateNewRootCA() async {
    if (!_initialized) {
      await _initCAConfig();
    }

    var generateRSAKeyPair = CryptoUtils.generateRSAKeyPair();
    var serverPubKey = generateRSAKeyPair.publicKey as RSAPublicKey;
    var serverPriKey = generateRSAKeyPair.privateKey as RSAPrivateKey;

    //根据CA证书subject来动态生成目标服务器证书的issuer和subject
    Map<String, String> x509Subject = {
      'C': 'CN',
      'ST': 'BJ',
      'L': 'Beijing',
      'O': 'Proxy',
      'OU': 'ProxyPin',
    };
    x509Subject['CN'] = 'ProxyPin CA (${Platform.localHostname})';

    var csrPem = X509Generate.generateSelfSignedCertificate(
      _caCert,
      serverPubKey,
      serverPriKey,
      825,
      sans: [x509Subject['CN']!],
      serialNumber: Random().nextInt(1000000).toString(),
      subject: x509Subject,
      keyUsage: x509.KeyUsage(x509.KeyUsage.keyCertSign | x509.KeyUsage.cRLSign),
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH, ExtendedKeyUsage.CLIENT_AUTH],
      basicConstraints: BasicConstraints(isCA: true),
    );

    //重新写入根证书
    var caFile = await certificateFile();
    await caFile.writeAsString(csrPem);

    //私钥
    var serverPriKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(serverPriKey);
    var keyFile = await privateKeyFile();
    await keyFile.writeAsString(serverPriKeyPem);
    cleanCache();
    _initialized = false;
  }

  ///重置默认根证书
  static Future<void> resetDefaultRootCA() async {
    var caFile = await certificateFile();
    await caFile.delete();

    var keyFile = await privateKeyFile();
    await keyFile.delete();
    cleanCache();
    _initialized = false;
  }

  static Future<void> _initCAConfig() async {
    if (_initialized) {
      return;
    }
    _serverKeyPair = CryptoUtils.generateRSAKeyPair();

    //从项目目录加入ca根证书
    var caPemFile = await certificateFile();
    _caCert = X509Utils.x509CertificateFromPem(await caPemFile.readAsString());
    //根据CA证书subject来动态生成目标服务器证书的issuer和subject

    //从项目目录加入ca私钥
    var keyFile = await privateKeyFile();
    _caPriKey = CryptoUtils.rsaPrivateKeyFromPem(await keyFile.readAsString());

    _initialized = true;
  }

  /// 证书文件
  static Future<File> certificateFile() async {
    final String appPath = await getApplicationSupportDirectory().then((value) => value.path);
    var caFile = File("$appPath${Platform.pathSeparator}ca.crt");
    if (!(await caFile.exists())) {
      var body = await FileRead.read('assets/certs/ca.crt');
      await caFile.writeAsBytes(body.buffer.asUint8List());
    }

    return caFile;
  }

  /// 私钥文件
  static Future<File> privateKeyFile() async {
    final String appPath = await getApplicationSupportDirectory().then((value) => value.path);
    var caFile = File("$appPath${Platform.pathSeparator}ca_key.pem");
    if (!(await caFile.exists())) {
      var body = await FileRead.read('assets/certs/ca_key.pem');
      await caFile.writeAsBytes(body.buffer.asUint8List());
    }

    return caFile;
  }

  ///生成 p12文件
  static Future<Uint8List> generatePkcs12(String? password) async {
    var caFile = await CertificateManager.certificateFile();
    var keyFile = await CertificateManager.privateKeyFile();
    return Pkcs12Utils.generatePkcs12(await keyFile.readAsString(), [await caFile.readAsString()], password: password);
  }
}
