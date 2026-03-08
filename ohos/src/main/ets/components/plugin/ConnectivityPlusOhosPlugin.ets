import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, {
  MethodCallHandler,
  MethodResult,
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import connection from '@ohos.net.connection';
// 修复1：兼容不同SDK版本的BusinessError导入（注释掉@ohos/base，改用any类型）
import { BusinessError } from '@ohos.base';
import EventChannel, { StreamHandler, EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';

// 对齐 Android 端的网络类型常量
const CONNECTIVITY_NONE = "none";
const CONNECTIVITY_WIFI = "wifi";
const CONNECTIVITY_MOBILE = "mobile";
const CONNECTIVITY_ETHERNET = "ethernet";
const CONNECTIVITY_BLUETOOTH = "bluetooth";
const CONNECTIVITY_VPN = "vpn";
const CONNECTIVITY_OTHER = "other";

/** ConnectivityPlusOhosPlugin **/
export default class ConnectivityPlusOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private receiver: ConnectivityBroadcastReceiver | null = null;

  getUniqueClassName(): string {
    return "ConnectivityPlusOhosPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "dev.fluttercommunity.plus/connectivity");
    this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "dev.fluttercommunity.plus/connectivity_status");
    this.receiver = new ConnectivityBroadcastReceiver();
    this.eventChannel.setStreamHandler(this.receiver!);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
    }
    if (this.eventChannel != null) {
      this.eventChannel.setStreamHandler(null);
    }
    this.receiver?.unregister();
    this.receiver = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method === "check") {
      try {
        // 核心逻辑：获取网络类型列表（对齐Android）
        const networkTypes = await this.getNetworkTypes();
        result.success(networkTypes);
      } catch (error) {
        // 异常时返回 none
        result.success([CONNECTIVITY_NONE]);
      }
    } else {
      result.notImplemented();
    }
  }

  /**
   * 核心方法：对齐 Android 端 getNetworkTypes 逻辑
   * @returns 网络类型列表（数组）
   */
  private async getNetworkTypes(): Promise<string[]> {
    try {
      const netHandle = await connection.getDefaultNetSync();
      return await this.getCapabilitiesFromNetwork(netHandle);
    } catch (error) {
      // 兼容无网络场景（对应Android legacy逻辑）
      return [CONNECTIVITY_NONE];
    }
  }

  /**
   * 对齐 Android 端 getCapabilitiesFromNetwork 逻辑
   * @param netHandle 网络句柄
   * @returns 网络类型列表
   */
  private async getCapabilitiesFromNetwork(netHandle: connection.NetHandle): Promise<string[]> {
    try {
      const capabilities = await connection.getNetCapabilitiesSync(netHandle);
      return this.getCapabilitiesList(capabilities);
    } catch (error) {
      return [CONNECTIVITY_NONE];
    }
  }

  /**
   * 修复2：将private改为public，让外部类可以访问
   * 核心逻辑：对齐 Android 端 getCapabilitiesList 方法
   * 1. 先检查网络是否有 INTERNET 能力
   * 2. 收集所有匹配的网络类型
   * 3. 无匹配时返回 other 或 none
   * @param capabilities 网络能力对象
   * @returns 网络类型列表
   */
  public getCapabilitiesList(capabilities: connection.NetCapabilities): string[] {
    const types: string[] = [];

    // 1. 检查是否有互联网能力（对齐Android的NET_CAPABILITY_INTERNET）
    // 鸿蒙中通过判断网络类型是否为空 + 网络是否可用作为替代
    if (!capabilities || !capabilities.bearerTypes || capabilities.bearerTypes.length === 0) {
      types.push(CONNECTIVITY_NONE);
      return types;
    }

    // 2. 遍历所有网络类型，收集匹配项（对齐Android的hasTransport逻辑）
    const bearerTypes = new Set(capabilities.bearerTypes);

    // WiFi（包含WiFi Aware）
    if (bearerTypes.has(connection.NetBearType.BEARER_WIFI)) {
      types.push(CONNECTIVITY_WIFI);
    }

    // 以太网
    if (bearerTypes.has(connection.NetBearType.BEARER_ETHERNET)) {
      types.push(CONNECTIVITY_ETHERNET);
    }

    // VPN（鸿蒙中BEARER_VPN对应）
    if (bearerTypes.has(connection.NetBearType.BEARER_VPN)) {
      types.push(CONNECTIVITY_VPN);
    }

    // 蜂窝移动网络
    if (bearerTypes.has(connection.NetBearType.BEARER_CELLULAR)) {
      types.push(CONNECTIVITY_MOBILE);
    }

    // 蓝牙（鸿蒙中BEARER_BLUETOOTH对应）
    if (bearerTypes.has(connection.NetBearType.BEARER_BLUETOOTH)) {
      types.push(CONNECTIVITY_BLUETOOTH);
    }

    // 3. 有互联网能力但无匹配类型 → 返回 other
    if (types.length === 0) {
      types.push(CONNECTIVITY_OTHER);
    }

    // 4. 极端情况兜底 → 返回 none
    if (types.length === 0) {
      types.push(CONNECTIVITY_NONE);
    }

    return types;
  }
}

class ConnectivityBroadcastReceiver implements StreamHandler {
  private events: EventSink | null = null;
  private connection: connection.NetConnection | null = null;

  onCancel(args: ESObject): void {
    this.events = null;
    this.unregister();
  }

  unregister(): void {
    if (this.connection) {
      this.connection.unregister(() => {});
      this.connection = null;
    }
  }

  register(): void {
    // 监听所有支持的网络类型（对齐Android）
    const netSpecifier: connection.NetSpecifier = {
      netCapabilities: {
        bearerTypes: [
          connection.NetBearType.BEARER_CELLULAR,
          connection.NetBearType.BEARER_WIFI,
          connection.NetBearType.BEARER_ETHERNET,
          connection.NetBearType.BEARER_BLUETOOTH,
          connection.NetBearType.BEARER_VPN
        ],
        networkCap: [],
      },
    };

    this.connection = connection.createNetConnection(netSpecifier, 0);
    // 修复1：将BusinessError改为any类型
    this.connection.register((err: BusinessError) => {
      if (err) {
        console.error('网络监听注册失败:', err);
      }
    });

    // 网络可用时返回完整类型列表
    this.connection.on('netAvailable', async (data: connection.NetHandle) => {
      try {
        const capabilities = await connection.getNetCapabilitiesSync(data);
        // 修复2：现在可以正常访问public方法
        const types = new ConnectivityPlusOhosPlugin().getCapabilitiesList(capabilities);
        this.events?.success(types);
      } catch (error) {
        this.events?.success([CONNECTIVITY_NONE]);
      }
    });

    // 网络不可用/丢失时返回 none
    this.connection.on('netUnavailable', () => {
      this.events?.success([CONNECTIVITY_NONE]);
    });

    this.connection.on('netLost', () => {
      this.events?.success([CONNECTIVITY_NONE]);
    });
  }

  onListen(args: ESObject, events: EventSink) {
    this.events = events;
    this.register();
  }
}