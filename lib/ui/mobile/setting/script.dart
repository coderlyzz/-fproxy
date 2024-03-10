﻿import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:network_proxy/network/components/script_manager.dart';
import 'package:network_proxy/network/util/logger.dart';
import 'package:network_proxy/ui/component/utils.dart';
import 'package:network_proxy/ui/component/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// @author wanghongen
/// 2023/10/19
/// js脚本
class MobileScript extends StatefulWidget {
  const MobileScript({super.key});

  @override
  State<StatefulWidget> createState() => _MobileScriptState();
}

bool _refresh = false;

/// 刷新脚本
void _refreshScript() {
  if (_refresh) {
    return;
  }
  _refresh = true;
  Future.delayed(const Duration(milliseconds: 1500), () async {
    _refresh = false;
    (await ScriptManager.instance).flushConfig();
  });
}

class _MobileScriptState extends State<MobileScript> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(localizations.script, style: const TextStyle(fontSize: 16))),
        body: Padding(
            padding: const EdgeInsets.only(left: 15, right: 10),
            child: futureWidget(
                ScriptManager.instance,
                loading: true,
                    (data) =>
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Row(children: [
                            SizedBox(
                                width: 300,
                                child: SwitchWidget(
                                  title: localizations.enableScript,
                                  subtitle: localizations.scriptUseDescribe,
                                  value: data.enabled,
                                  onChanged: (value) {
                                    data.enabled = value;
                                    _refreshScript();
                                  },
                                )),
                          ]),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                  icon: const Icon(Icons.add, size: 18),
                                  onPressed: scriptEdit,
                                  label: Text(localizations.add)),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                icon: const Icon(Icons.input_rounded, size: 18),
                                onPressed: import,
                                label: Text(localizations.import),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Expanded(child: ScriptList(scripts: data.list)),
                        ]))));
  }

  //导入js
  import() async {
    final XFile? file = await openFile();
    if (file == null) {
      return;
    }

    try {
      var scriptManager = (await ScriptManager.instance);
      var json = jsonDecode(utf8.decode(await file.readAsBytes()));

      if (json is List<dynamic>) {
        for (var item in json) {
          var scriptItem = ScriptItem.fromJson(item);
          await scriptManager.addScript(scriptItem, item['script']);
        }
      } else {
        var scriptItem = ScriptItem.fromJson(json);
        await scriptManager.addScript(scriptItem, json['script']);
      }

      _refreshScript();
      if (mounted) {
        FlutterToastr.show(localizations.importSuccess, context);
      }
      setState(() {});
    } catch (e, t) {
      logger.e('导入失败 $file', error: e, stackTrace: t);
      if (mounted) {
        FlutterToastr.show("${localizations.importFailed} $e", context);
      }
    }
  }

  /// 添加脚本
  scriptEdit() async {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ScriptEdit())).then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }
}

/// 编辑脚本
class ScriptEdit extends StatefulWidget {
  final ScriptItem? scriptItem;
  final String? script;

  const ScriptEdit({super.key, this.scriptItem, this.script});

  @override
  State<StatefulWidget> createState() => _ScriptEditState();
}

class _ScriptEditState extends State<ScriptEdit> {
  late CodeController script;
  late TextEditingController nameController;
  late TextEditingController urlController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    script = CodeController(language: javascript, text: widget.script ?? ScriptManager.template);
    nameController = TextEditingController(text: widget.scriptItem?.name);
    urlController = TextEditingController(text: widget.scriptItem?.url);
  }

  @override
  void dispose() {
    script.dispose();
    nameController.dispose();
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    GlobalKey formKey = GlobalKey<FormState>();
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Scaffold(
        appBar: AppBar(
            title: Row(children: [
              Text(localizations.scriptEdit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              Text.rich(TextSpan(
                  text: localizations.useGuide,
                  style: const TextStyle(color: Colors.blue, fontSize: 14),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () =>
                        launchUrl(Uri.parse(isCN
                            ? 'https://gitee.com/wanghongenpin/network-proxy-flutter/wikis/%E8%84%9A%E6%9C%AC'
                            : 'https://github.com/wanghongenpin/network_proxy_flutter/wiki/Script')))),
            ]),
            actions: [
              TextButton(
                  onPressed: () async {
                    if (!(formKey.currentState as FormState).validate()) {
                      FlutterToastr.show("${localizations.name} URL ${localizations.cannotBeEmpty}", context,
                          position: FlutterToastr.top);
                      return;
                    }
                    //新增
                    var scriptManager = await ScriptManager.instance;
                    if (widget.scriptItem == null) {
                      var scriptItem = ScriptItem(true, nameController.text, urlController.text);
                      await scriptManager.addScript(scriptItem, script.text);
                    } else {
                      widget.scriptItem?.name = nameController.text;
                      widget.scriptItem?.url = urlController.text;
                      widget.scriptItem?.urlReg = null;
                      await scriptManager.updateScript(widget.scriptItem!, script.text);
                    }

                    _refreshScript();
                    if (context.mounted) {
                      Navigator.of(context).maybePop(true);
                    }
                  },
                  child: Text(localizations.save)),
            ]),
        body: Padding(
            padding: const EdgeInsets.only(left: 15, right: 10, bottom: 20),
            child: Form(
                key: formKey,
                child: ListView(
                  children: [
                    textField("${localizations.name}:", nameController, localizations.pleaseEnter),
                    const SizedBox(height: 10),
                    textField("URL:", urlController, "github.com/api/*", keyboardType: TextInputType.url),
                    const SizedBox(height: 10),
                    Text("${localizations.script}:"),
                    const SizedBox(height: 5),
                    CodeTheme(
                        data: CodeThemeData(styles: monokaiSublimeTheme),
                        child: SingleChildScrollView(
                            child: CodeField(textStyle: const TextStyle(fontSize: 14), controller: script)))
                  ],
                ))));
  }

  Widget textField(String label, TextEditingController controller, String hint, {TextInputType? keyboardType}) {
    return Row(children: [
      SizedBox(width: 50, child: Text(label)),
      Expanded(
          child: TextFormField(
            controller: controller,
            validator: (val) => val?.isNotEmpty == true ? null : "",
            keyboardType: keyboardType,
            decoration: InputDecoration(
                hintText: hint,
                contentPadding: const EdgeInsets.all(10),
                errorStyle: const TextStyle(height: 0, fontSize: 0),
                focusedBorder: focusedBorder(),
                isDense: true,
                border: const OutlineInputBorder()),
          ))
    ]);
  }

  InputBorder focusedBorder() {
    return OutlineInputBorder(borderSide: BorderSide(color: Theme
        .of(context)
        .colorScheme
        .primary, width: 2));
  }
}

/// 脚本列表
class ScriptList extends StatefulWidget {
  final List<ScriptItem> scripts;

  const ScriptList({super.key, required this.scripts});

  @override
  State<ScriptList> createState() => _ScriptListState();
}

class _ScriptListState extends State<ScriptList> {
  Set<int> selected = {};
  bool multiple = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        persistentFooterButtons: [multiple ? globalMenu() : const SizedBox()],
        body: Container(
            padding: const EdgeInsets.only(top: 10, bottom: 30),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
            child: Scrollbar(
                child: ListView(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(width: 100, padding: const EdgeInsets.only(left: 10), child: Text(localizations.name)),
                      SizedBox(width: 50, child: Text(localizations.enable, textAlign: TextAlign.center)),
                      const VerticalDivider(),
                      const Expanded(child: Text("URL")),
                    ],
                  ),
                  const Divider(thickness: 0.5),
                  Column(children: rows(widget.scripts))
                ]))));
  }

  globalMenu() {
    return Stack(children: [
      Container(
          height: 50,
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2)))),
      Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
              child: TextButton(
                  onPressed: () {},
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    TextButton.icon(
                        onPressed: () {
                          export(selected.toList());
                          setState(() {
                            selected.clear();
                            multiple = false;
                          });
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: Text(localizations.export, style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                        onPressed: () => removeScripts(selected.toList()),
                        icon: const Icon(Icons.delete, size: 18),
                        label: Text(localizations.delete, style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                        onPressed: () {
                          setState(() {
                            multiple = false;
                            selected.clear();
                          });
                        },
                        icon: const Icon(Icons.cancel, size: 18),
                        label: Text(localizations.cancel, style: const TextStyle(fontSize: 14))),
                  ]))))
    ]);
  }

  List<Widget> rows(List<ScriptItem> list) {
    var primaryColor = Theme
        .of(context)
        .colorScheme
        .primary;

    return List.generate(list.length, (index) {
      return InkWell(
          splashColor: primaryColor.withOpacity(0.3),
          onTap: () async {
            if (multiple) {
              setState(() {
                if (!selected.add(index)) {
                  selected.remove(index);
                }
              });
              return;
            }
            showEdit(index);
          },
          onLongPress: () => showMenus(index),
          child: Container(
              color: selected.contains(index)
                  ? primaryColor.withOpacity(0.8)
                  : index.isEven
                  ? Colors.grey.withOpacity(0.1)
                  : null,
              height: 45,
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  SizedBox(
                      width: 100,
                      child: Text(list[index].name!,
                          style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                  SizedBox(
                      width: 50,
                      child: Transform.scale(
                          scale: 0.65,
                          child: SwitchWidget(
                              value: list[index].enabled,
                              onChanged: (val) {
                                list[index].enabled = val;
                                _refreshScript();
                              }))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(list[index].url, style: const TextStyle(fontSize: 13))),
                ],
              )));
    });
  }

  //点击菜单
  showMenus(int index) {
    setState(() {
      selected.add(index);
    });

    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        enableDrag: true,
        builder: (context) {
          return Wrap(
            alignment: WrapAlignment.center,
            children: [
              BottomSheetItem(
                  text: localizations.multiple,
                  onPressed: () {
                    setState(() => multiple = true);
                  }),
              const Divider(thickness: 0.5, height: 1),
              BottomSheetItem(text: localizations.edit, onPressed: () => showEdit(index)),
              const Divider(thickness: 0.5, height: 1),
              BottomSheetItem(text: localizations.share, onPressed: () => export([index])),
              const Divider(thickness: 0.5, height: 1),
              BottomSheetItem(
                  text: widget.scripts[index].enabled ? localizations.disabled : localizations.enable,
                  onPressed: () {
                    widget.scripts[index].enabled = !widget.scripts[index].enabled;
                    _refreshScript();
                  }),
              const Divider(thickness: 0.5, height: 1),
              BottomSheetItem(
                  text: localizations.delete,
                  onPressed: () async {
                    await (await ScriptManager.instance).removeScript(index);
                    _refreshScript();
                    if (context.mounted) FlutterToastr.show(localizations.importSuccess, context);
                  }),
              Container(color: Theme
                  .of(context)
                  .hoverColor, height: 8),
              TextButton(
                child: Container(
                    height: 50,
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(localizations.cancel, textAlign: TextAlign.center)),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        }).then((value) {
      setState(() {
        selected.remove(index);
      });
    });
  }

  showEdit([int? index]) async {
    String? script = index == null ? null : await (await ScriptManager.instance).getScript(widget.scripts[index]);
    if (!mounted) {
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(
        builder: (context) => ScriptEdit(scriptItem: index == null ? null : widget.scripts[index], script: script)))
        .then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }

  //导出js
  export(List<int> indexes) async {
    if (indexes.isEmpty) return;
    //文件名称
    String fileName = 'proxypin-scripts.json';
    var scriptManager = await ScriptManager.instance;
    List<dynamic> json = [];
    for (var idx in indexes) {
      var item = widget.scripts[idx];
      var map = item.toJson();
      map.remove("scriptPath");
      map['script'] = await scriptManager.getScript(item);
      json.add(map);
    }

    final XFile file = XFile.fromData(utf8.encode(jsonEncode(json)), mimeType: 'json');
    Share.shareXFiles([file], subject: fileName);
  }

  enableStatus(bool enable) {
    for (var idx in selected) {
      widget.scripts[idx].enabled = enable;
    }
    setState(() {});
    _refreshScript();
  }

  removeScripts(List<int> indexes) async {
    if (indexes.isEmpty) return;
    showConfirmDialog(context, content: localizations.confirmContent, onConfirm: () async {
      var scriptManager = await ScriptManager.instance;
      for (var idx in indexes) {
        await scriptManager.removeScript(idx);
      }

      setState(() {
        selected.clear();
      });
      _refreshScript();

      if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
    });
  }
}
