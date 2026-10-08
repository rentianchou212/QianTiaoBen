// 欠条本 · 数据库管理器（单例）
// 基于 RelationalStore（底层 SQLite），应用私有数据库，无需任何权限
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'QianTiaoBenDB';

// 借出记录表
const CREATE_LOANS: string = `
  CREATE TABLE IF NOT EXISTS loans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person TEXT NOT NULL,
    amount_cents INTEGER NOT NULL,
    loan_date TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
  )`;

// 还款记录表
const CREATE_REPAYMENTS: string = `
  CREATE TABLE IF NOT EXISTS repayments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id INTEGER NOT NULL,
    amount_cents INTEGER NOT NULL,
    repay_date TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT ''
  )`;

// 还款表按借款 id 建索引（汇总 JOIN 查询提速）
const CREATE_REPAY_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_repayments_loan ON repayments(loan_id)';

export class DbManager {
  private static instance: DbManager | null = null;
  private store: relationalStore.RdbStore | null = null;

  private constructor() {
  }

  public static getInstance(): DbManager {
    if (DbManager.instance === null) {
      DbManager.instance = new DbManager();
    }
    return DbManager.instance;
  }

  // 初始化并建表（幂等：可安全重复调用，已初始化则直接返回）
  public async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'qiantiaoben.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    await store.executeSql(CREATE_LOANS);
    await store.executeSql(CREATE_REPAYMENTS);
    await store.executeSql(CREATE_REPAY_INDEX);
    this.store = store;
    hilog.info(0x0000, TAG, 'db ready: qiantiaoben.db');
  }

  // 获取数据库实例（未初始化则抛错，用于尽早暴露调用顺序问题）
  public getStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('DbManager not initialized: call init() first');
    }
    return this.store;
  }
}
