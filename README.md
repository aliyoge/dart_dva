# dart_dva
[![pub package](https://img.shields.io/pub/v/dart_dva.svg)](https://pub.dartlang.org/packages/dart_dva)

Dart版本的轻量Dva。

简化Redux使用流程，将你从Action的命名和创建的繁琐步骤中解救出来。

并且提供Action异步方案。

该项目目前还在开发阶段。

## 使用方法

```dart
import 'dart:async';

import 'package:meta/meta.dart';

import 'package:dart_dva/dart_dva.dart';

class UserInfo {
  String name;
  int id;
  UserInfo({@required this.id, this.name = 'init'});
}

class LoginState {
  bool loading;
  UserInfo info;
  LoginState({this.loading = false, this.info});

  LoginState copyWith(payload) {
    return LoginState(
      loading:
          payload.containsKey('loading') ? payload['loading'] : this.loading,
      info: payload.containsKey('info') ? payload['info'] : this.info,
    );
  }
}

Future<UserInfo> asyncInfo() async {
  final info = await new Future.delayed(new Duration(seconds: 3), () {
    return UserInfo(id: 3, name: 'newname_3');
  });
  return info;
}

void main() {
  final loginModel = DvaModel<LoginState>(
  namespace: 'login', 
  state: LoginState(), 
  effects: [
    DvaEffect(
        type: 'getUserinfo',
        handler: (Store store, DvaAction action, DvaUtils utils) async {
          final newinfo = await asyncInfo();
          utils.put(DvaAction(
              type: 'save', payload: {'info': newinfo, 'loading': true}));
        })
  ], reducers: [
    DvaReducer<LoginState>(
        type: 'save',
        handler: (LoginState state, DvaAction action) {
          return state.copyWith(action.payload);
        }),
  ]);

  final dva = Dva.create(models: [loginModel]);
  final store = dva.store;

  // store.dispatch(DvaAction(type: 'login/save', payload: {'loading': true, 'info': 2}));
  dva.dispatch(DvaAction(type: 'login/getUserinfo')).then((_) {
    print(store.state['login'].info.name);
    dva.dispatch(DvaAction(
        type: 'login/save',
        payload: {'info': UserInfo(id: 5, name: 'finalname')})).then((_) {
          print(store.state['login'].info.name);
        });
  });
}
```



