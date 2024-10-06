/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'dart:convert';
import 'dart:io';

import 'package:easy_permission/easy_permission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:network_proxy/native/vpn.dart';
import 'package:network_proxy/network/bin/configuration.dart';
import 'package:network_proxy/network/bin/server.dart';
import 'package:network_proxy/network/components/host_filter.dart';
import 'package:network_proxy/network/components/request_rewrite_manager.dart';
import 'package:network_proxy/network/components/script_manager.dart';
import 'package:network_proxy/network/http_client.dart';
import 'package:network_proxy/network/util/logger.dart';
import 'package:network_proxy/ui/component/utils.dart';
import 'package:network_proxy/ui/component/widgets.dart';
import 'package:network_proxy/utils/ip.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrscan/qrscan.dart' as scanner;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

///远程设备
///Remote device
///@author Hongen Wang
class RemoteModel {
  final bool connect;
  final String? host;
  final int? port;
  final String? os;
  final String? hostname;

  RemoteModel({
    required this.connect,
    this.host,
    this.port,
    this.os,
    this.hostname,
  });

  factory RemoteModel.fromJson(Map<String, dynamic> json) {
    return RemoteModel(
      connect: json['connect'],
      host: json['host'],
      port: json['port'],
      os: json['os'],
      hostname: json['hostname'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'connect': connect,
      'host': host,
      'port': port,
      'os': os,
      'hostname': hostname,
    };
  }
}

class RemoteDevicePage extends StatefulWidget {
  final ProxyServer proxyServer;
  final ValueNotifier<RemoteModel> remoteDevice;

  const RemoteDevicePage({super.key, required this.proxyServer, required this.remoteDevice});

  @override
  State<RemoteDevicePage> createState() => _RemoteDevicePageState();
}

class _RemoteDevicePageState extends State<RemoteDevicePage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  bool syncConfig = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(localizations.remoteDevice, style: const TextStyle(fontSize: 16)),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.add_outlined),
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry>[
                CustomPopupMenuItem(
                    height: 32,
                    child: ListTile(
                        leading: const Icon(Icons.qr_code_scanner_outlined),
                        dense: true,
                        title: Text(localizations.scanCode),
                        onTap: () => connectRemote(context))),
                // CustomPopupMenuItem(
                //     height: 32,
                //     child: ListTile(
                //         leading: const Icon(Icons.edit_rounded),
                //         dense: true,
                //         title: Text(localizations.inputAddress),
                //         onTap: () {})),
                PopupMenuItem(
                    height: 32,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.phone_android),
                      title: Text(localizations.myQRCode),
                      onTap: () async {
                        Navigator.maybePop(context);
                        var ip = await localIp(readCache: false);
                        if (context.mounted) {
                          qrCode(context, ip, widget.proxyServer.port);
                        }
                      },
                    )),
              ];
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            remoteDeviceStatus(), //远程设备状态
            const SizedBox(height: 20),
            Text(localizations.remoteDeviceList, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Expanded(child: futureWidget(SharedPreferences.getInstance(), rows)), //远程设备列表
          ],
        ),
      ),
    );
  }

  Widget rows(SharedPreferences prefs) {
    var remoteDeviceList = prefs.getStringList('remoteDeviceList') ?? [];

    return ListView(
      children: remoteDeviceList.map((it) {
        var remoteDevice = RemoteModel.fromJson(jsonDecode(it));
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 5),
          title: Text(remoteDevice.hostname ?? ''),
          subtitle: Text('${remoteDevice.host}:${remoteDevice.port}'),
          trailing: getIcon(remoteDevice.os!),
          onTap: () {
            doConnect(remoteDevice.host!, remoteDevice.port!);
          },
        );
      }).toList(),
    );
  }

  Icon getIcon(String os) {
    if (os.contains("windows")) {
      return const Icon(Icons.window_sharp, size: 30);
    } else if (os.contains("linux")) {
      return const Icon(Icons.desktop_windows, size: 30);
    } else if (os.contains("macos") || os.contains("ios")) {
      return const Icon(Icons.apple, size: 30);
    } else if (os == 'android') {
      return const Icon(Icons.android, size: 30);
    } else {
      return const Icon(Icons.devices, size: 30);
    }
  }

  ///远程设备状态
  Widget remoteDeviceStatus() {
    if (widget.remoteDevice.value.connect) {
      return Center(
          child: Column(
        children: [
          const Icon(Icons.check_circle_outline_outlined, size: 55, color: Colors.green),
          Text('${localizations.connected}：${widget.remoteDevice.value.hostname}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            TextButton.icon(
              style: ButtonStyle(
                  shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)))),
              onPressed: pullConfig,
              icon: const Icon(Icons.sync),
              label: Text(localizations.syncConfig),
            ),
            TextButton.icon(
              label: Text(localizations.disconnect),
              style: ButtonStyle(
                shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0))),
              ),
              icon: const Icon(Icons.cancel_outlined),
              onPressed: () {
                widget.remoteDevice.value = RemoteModel(connect: false);
                setState(() {});
              },
            ),
          ])
        ],
      ));
    }

    return Center(
        child: Column(children: [
      const Icon(Icons.cancel_outlined, size: 55, color: Colors.red),
      const SizedBox(height: 6),
      Text(localizations.notConnected, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    ]));
  }

  ///扫码连接
  connectRemote(BuildContext context) async {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    String scanRes;
    if (Platform.isAndroid) {
      await EasyPermission.requestPermissions([PermissionType.CAMERA]);
      scanRes = await scanner.scan() ?? "-1";
    } else {
      scanRes = await FlutterBarcodeScanner.scanBarcode("#ff6666", localizations.cancel, true, ScanMode.QR);
    }
    if (scanRes == "-1") return;
    if (scanRes.startsWith("http")) {
      launchUrl(Uri.parse(scanRes), mode: LaunchMode.externalApplication);
      return;
    }

    if (scanRes.startsWith("proxypin://connect")) {
      Uri uri = Uri.parse(scanRes);
      var host = uri.queryParameters['host'];
      var port = uri.queryParameters['port'];

      doConnect(host!, int.parse(port!));
    }

    if (context.mounted) {
      FlutterToastr.show(localizations.invalidQRCode, context);
    }
  }

  doConnect(String host, int port) async {
    try {
      var response = await HttpClients.get("http://$host:$port/ping").timeout(const Duration(seconds: 3));
      if (response.bodyAsString == "pong") {
        widget.remoteDevice.value = RemoteModel(
            connect: true,
            host: host,
            port: port,
            os: response.headers.get("os"),
            hostname: response.headers.get("hostname"));

        //去重记录5条连接记录
        SharedPreferences prefs = await SharedPreferences.getInstance();
        var remoteDeviceList = prefs.getStringList('remoteDeviceList') ?? [];
        var value = jsonEncode(widget.remoteDevice.value.toJson());
        remoteDeviceList.remove(value);
        remoteDeviceList.insert(0, value);
        prefs.setStringList('remoteDeviceList', remoteDeviceList).then((value) {
          setState(() {});
        });

        if (mounted && Navigator.canPop(context)) {
          FlutterToastr.show(
              "${localizations.connectSuccess}${Vpn.isVpnStarted ? '' : ', ${localizations.remoteConnectSuccessTips}'}",
              context,
              duration: 3);
        }
      }
    } catch (e) {
      logger.e(e);
      if (mounted) {
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(content: Text(localizations.remoteConnectFail));
            });
      }
    }
  }

  ///连接二维码
  qrCode(BuildContext context, String host, int port) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            contentPadding: const EdgeInsets.all(15),
            actionsPadding: const EdgeInsets.only(bottom: 10, right: 10),
            title: Text(localizations.remoteConnectForward, style: const TextStyle(fontSize: 16)),
            content: SizedBox(
                height: 280,
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      backgroundColor: Colors.white,
                      data: "proxypin://connect?host=$host&port=${widget.proxyServer.port}",
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${localizations.localIP}:'),
                        const SizedBox(width: 5),
                        SelectableText('$host:$port'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(localizations.mobileScan),
                  ],
                )),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(localizations.cancel)),
            ],
          );
        });
  }

  //拉取桌面配置
  pullConfig() {
    var desktopModel = widget.remoteDevice.value;
    HttpClients.get('http://${desktopModel.host}:${desktopModel.port}/config').then((response) {
      if (response.status.isSuccessful()) {
        var config = jsonDecode(response.bodyAsString);
        syncConfig = true;
        showDialog(
            context: context,
            builder: (context) {
              return ConfigSyncWidget(configuration: widget.proxyServer.configuration, config: config);
            });
      }
    }).onError((error, stackTrace) {
      logger.e('拉取配置失败', error: error, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.pullConfigFail)));
    });
  }
}

class ConfigSyncWidget extends StatefulWidget {
  final Configuration configuration;
  final Map<String, dynamic> config;

  const ConfigSyncWidget({super.key, required this.configuration, required this.config});

  @override
  State<StatefulWidget> createState() {
    return ConfigSyncState();
  }
}

class ConfigSyncState extends State<ConfigSyncWidget> {
  bool syncWhiteList = true;
  bool syncBlackList = true;
  bool syncRewrite = true;
  bool syncScript = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(localizations.syncConfig, style: const TextStyle(fontSize: 16)),
      content: Wrap(children: [
        SwitchWidget(
            title: "${localizations.sync}${localizations.domainWhitelist}",
            value: syncWhiteList,
            onChanged: (val) {
              setState(() {
                syncWhiteList = val;
              });
            }),
        const SizedBox(height: 5),
        SwitchWidget(
            title: "${localizations.sync}${localizations.domainBlacklist}",
            value: syncBlackList,
            onChanged: (val) {
              setState(() {
                syncBlackList = val;
              });
            }),
        const SizedBox(height: 5),
        SwitchWidget(
            title: "${localizations.sync}${localizations.requestRewrite}",
            value: syncRewrite,
            onChanged: (val) {
              setState(() {
                syncRewrite = val;
              });
            }),
        const SizedBox(height: 5),
        SwitchWidget(
            title: "${localizations.sync}${localizations.script}",
            value: syncScript,
            onChanged: (val) {
              setState(() {
                syncScript = val;
              });
            }),
      ]),
      actions: [
        TextButton(
            child: Text(localizations.cancel),
            onPressed: () {
              Navigator.pop(context);
            }),
        TextButton(
            child: Text('${localizations.start}${localizations.sync}'),
            onPressed: () async {
              if (syncWhiteList) {
                HostFilter.whitelist.load(widget.config['whitelist']);
              }
              if (syncBlackList) {
                HostFilter.blacklist.load(widget.config['blacklist']);
              }
              widget.configuration.flushConfig();

              if (syncRewrite) {
                var requestRewrites = await RequestRewrites.instance;
                await requestRewrites.syncConfig(widget.config['requestRewrites']);
              }

              if (syncScript) {
                var scriptManager = await ScriptManager.instance;
                await scriptManager.clean();
                scriptManager.list.clear();
                for (var item in widget.config['scripts']) {
                  await scriptManager.addScript(ScriptItem.fromJson(item), item['script']);
                }
                await scriptManager.flushConfig();
              }

              if (mounted) {
                Navigator.pop(this.context);
                ScaffoldMessenger.of(this.context)
                    .showSnackBar(SnackBar(content: Text('${localizations.sync}${localizations.success}')));
              }
            }),
      ],
    );
  }
}
