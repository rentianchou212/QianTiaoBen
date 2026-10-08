// 欠条本 · 数据模型与工具函数
// 金额一律以「分」(整数) 存储，避免浮点误差；展示时再转成「元」文本

// 借款记录（loans 表一行）
export interface Loan {
  id: number;
  person: string;       // 借款人
  amountCents: number;  // 借出金额（分）
  loanDate: string;     // 借出日期 YYYY-MM-DD
  note: string;         // 备注
}

// 借款 + 已还汇总（总览列表使用，已还金额来自 repayments 实时汇总）
export interface LoanSummary {
  id: number;
  person: string;
  amountCents: number;  // 借出金额（分）
  repaidCents: number;  // 已还金额（分）
  loanDate: string;
  note: string;
}

// 按借款人维度汇总（首页列表使用）
export interface PersonSummary {
  person: string;       // 借款人（分组键）
  loanCount: number;    // 借款笔数
  amountCents: number;  // 总借出（分）
  repaidCents: number;  // 已还（分）
}

// 还款记录（repayments 表一行）
export interface Repayment {
  id: number;
  loanId: number;       // 关联的借款 id
  amountCents: number;  // 还款金额（分）
  repayDate: string;    // 还款日期 YYYY-MM-DD
  note: string;
}

// 元 -> 分（1234.56 -> 123456）
export function yuanToCents(yuan: number): number {
  return Math.round(yuan * 100);
}

// 分 -> 元文本（123456 -> '1234.56'，负数带负号）
export function centsToYuanText(cents: number): string {
  const sign: string = cents < 0 ? '-' : '';
  const abs: number = Math.abs(cents);
  const yuan: number = Math.floor(abs / 100);
  const fen: number = abs % 100;
  const fenText: string = fen < 10 ? `0${fen}` : `${fen}`;
  return `${sign}${yuan}.${fenText}`;
}

// 今天的日期文本 YYYY-MM-DD
export function todayText(): string {
  const d: Date = new Date();
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const mm: string = m < 10 ? `0${m}` : `${m}`;
  const dd: string = day < 10 ? `0${day}` : `${day}`;
  return `${d.getFullYear()}-${mm}-${dd}`;
}

// 当前时间文本（created_at 使用，ISO 格式便于排序）
export function nowText(): string {
  return new Date().toISOString();
}
