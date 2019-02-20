library dart_dva;

import 'dart:async';

import 'package:meta/meta.dart';

import 'package:redux/redux.dart';

export 'package:redux/redux.dart';


class DvaError {
  int code;
  String message;
  DvaError(this.code, [this.message]);
}

class DvaAction {
  String type;
  dynamic payload;

  String get callbackToken => _callbackToken;
  String _callbackToken;
  setToken(String token) {
    _callbackToken = token;
  }

  Function get callback => _callback;
  Function _callback;
  setCallback(Function func) {
    _callback = func;
  }

  DvaAction({@required this.type, this.payload});
  toJson() {
    return {'type': this.type, 'payload': this.payload};
  }
}

class DvaReducer<State> {
  final String type;
  final State Function(State state, DvaAction action) handler;
  DvaReducer({@required this.type, @required this.handler});
}

/// ***
/// create an model
/// ***
class DvaModel<State> {
  String namespace;
  State state;
  Iterable<DvaEffect> effects;
  Iterable<DvaReducer> reducers;

  DvaModel({@required this.namespace, this.state, this.effects, this.reducers});
}

typedef Future<Null> EffectHandler(
    Store store, DvaAction action, DvaUtils utils);

/// ***
/// Async
/// ***
class DvaEffect {
  final String type;
  final EffectHandler handler;
  DvaEffect({@required this.type, @required this.handler});
}

///可以监听异步完成的dispatch
typedef Future DvaDispatch(DvaAction action);

typedef Future Put(DvaAction action);
// TODO: Call函数还没有实现
typedef void Call(Function func);

class DvaUtils {
  DvaDispatch dispatch;
  Put put;
  Call call;
  DvaUtils({@required this.dispatch, @required this.put, this.call});
}

class Dva {
  Store get store => _store;

  Store _store;

  ///dav入口，创建store
  Dva.create(
      {@required List models,
      List<Middleware> middleware = const [],
      bool syncStream = false,
      bool distinct = false}) {
    var initialState = new Map();
    var reducerMap = new Map();
    var effectList = middleware.sublist(0);
    for (var model in models) {
      if (!(model is DvaModel)) {
        throw new Exception('models must be [DvaModel] List');
      }
      if (initialState.containsKey(model.namespace)) {
        throw new Exception('can not has this same namespace');
      }
      if (null == model.state) {
        throw new Exception('every model need initialstate');
      }
      // init app state
      initialState[model.namespace] = model.state;

      // init model reducers
      final rdcs = model.reducers
          .map((rdcObj) => _makeReducer(
              type: '${model.namespace}/${rdcObj.type}',
              handler: rdcObj.handler))
          .toList();
      reducerMap[model.namespace] = _combineReducers(rdcs);

      if (model.effects != null && model.effects.length > 0) {
        // init model effects
        final effs = model.effects
            .map((effObj) => _makeEffect(
                namespace: model.namespace,
                type: '${model.namespace}/${effObj.type}',
                handler: effObj.handler))
            .toList();
        effectList.add(_combineEffects(effs));
      }
    }
    // init app reducers
    Reducer<Map> reducer = (Map state, dynamic action) {
      var newState = new Map();
      for (var namespace in reducerMap.keys) {
        newState[namespace] = reducerMap[namespace](state[namespace], action);
      }
      return newState;
    };

    _store = Store<Map>(
      reducer,
      initialState: initialState,
      middleware: effectList,
      syncStream: syncStream,
      distinct: distinct,
    );
  }

  ///可监听dispatch完成，返回最新的State
  Future<Map> dispatch(DvaAction action) => _dispatch(_store, action);

  ///内部使用的
  Future<Map> _dispatch(Store store, DvaAction action) async {
    // 创建此dispatch执行完回调
    var _completer = Completer<Map>();
    action.setCallback(() {
      if (!_completer.isCompleted) {
        _completer.complete(store.state);
      }
    });

    // 触发dispatch
    store.dispatch(action);

    // 超时没有回调，手动设置为error
    Future.delayed(Duration(seconds: 30), () {
      if (!_completer.isCompleted) {
        _completer.completeError(DvaError(9990, 'Dispatch timeout'));
      }
    });
    return _completer.future;
  }

  /// ***
  /// Action is Map
  /// Type is String
  /// ***
  Reducer<State> _makeReducer<State>(
      {@required String type, @required dynamic handler // DvaReducer<State>
      }) {
    return (State state, dynamic action) {
      //TODO:处理没有找到action的回调情况
      if (action.type == type) {
        var newState = handler(state, action);
        // dispatch回调
        if (action.callback != null && action.callback is Function) {
          Future.delayed(Duration(milliseconds: 1), () {
            action.callback();
          });
        }
        return newState;
      }
      return state;
    };
  }

  Reducer<State> _combineReducers<State>(List reducers) {
    return (State state, dynamic action) {
      for (final reducer in reducers) {
        state = reducer(state, action);
      }
      return state;
    };
  }

  ///生成副作用
  Middleware _makeEffect(
      {@required String namespace,
      @required String type,
      @required EffectHandler handler}) {
    return (Store store, dynamic action, NextDispatcher next) async {
      if (action.type == type) {
        // TODO: 副作用在这一步产生异步操作，使得结果不可预期。此处需要优化
        await handler(
            store, action, _makeUtils(namespace: namespace, store: store));
        // 等待异步完成后回调
        if (action.callback != null && action.callback is Function) {
          action.callback();
        }
      } else {
        next(action);
      }
    };
  }

  ///生成put disptach 等函数供effect使用
  DvaUtils _makeUtils({
    @required Store store,
    @required String namespace,
  }) {
    return DvaUtils(
      dispatch: (DvaAction action) async {
      return _dispatch(store, action);
    }, put: (DvaAction action) async {
      String type = '$namespace/${action.type}';
      return _dispatch(store, DvaAction(type: type, payload: action.payload));
    });
  }

  ///合并副作用
  Middleware _combineEffects(List effects) {
    return (Store store, dynamic action, NextDispatcher next) {
      for (final effect in effects) {
        effect(store, action, next);
      }
    };
  }
}

///Tools 工具方法
dynamic copyValue(
    {@required dynamic old,
    @required String key,
    @required Map<String, dynamic> newMap}) {
  return newMap.containsKey(key) ? newMap[key] : old;
}
