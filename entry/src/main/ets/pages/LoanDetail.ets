// 详情页：借款信息 + 还款记录 + 记一笔还款 + 编辑入口
// 交互：右上角「编辑」改借款信息；底部按钮记还款；长按还款记录删除该笔
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { DbManager } from '../database/DbManager';
import { LoanDao } from '../database/LoanDao';
import { RepaymentDao } from '../database/RepaymentDao';
import { LoanSummary, Repayment, centsToYuanText, todayText, yuanToCents } from '../model/LoanModels';

@Entry
@Component
struct LoanDetail {
  @State loan: LoanSummary = { id: 0, person: '', amountCents: 0, repaidCents: 0, loanDate: '', note: '' };
  @State hasLoan: boolean = false;
  @State repayments: Repayment[] = [];
  @State loaded: boolean = false;
  @State errorMsg: string = '';
  @State showPanel: boolean = false;      // 记还款面板
  @State repayAmountText: string = '';
  @State repayDate: string = todayText();
  @State repayNote: string = '';
  @State repaySaving: boolean = false;
  @State repayError: string = '';

  private loanId: number = 0;
  private loanDao: LoanDao = new LoanDao();
  private repayDao: RepaymentDao = new RepaymentDao();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, number>;
    if (params) {
      const id: number = params['loanId'];
      if (typeof id === 'number' && id > 0) {
        this.loanId = id;
        this.loadData();
        return;
      }
    }
    this.errorMsg = '参数错误';
    this.loaded = true;
  }

  // 从编辑页返回时刷新
  onPageShow(): void {
    if (this.loanId > 0) {
      this.loadData();
    }
  }

  // 待收金额（分），多还的部分不显示为负数
  private pendingCents(): number {
    return Math.max(0, this.loan.amountCents - this.loan.repaidCents);
  }

  private async loadData(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await DbManager.getInstance().init(ctx);
      const s: LoanSummary | null = await this.loanDao.getSummaryById(this.loanId);
      if (s === null) {
        this.hasLoan = false;
      } else {
        this.loan = s;
        this.hasLoan = true;
      }
      this.repayments = await this.repayDao.getByLoan(this.loanId);
      this.loaded = true;
      this.errorMsg = '';
    } catch (e) {
      this.errorMsg = `加载失败: ${(e as Error).message}`;
      this.loaded = true;
    }
  }

  private pickRepayDate(): void {
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(this.repayDate),
      onDateAccept: (value: Date) => {
        const m: number = value.getMonth() + 1;
        const d: number = value.getDate();
        const mm: string = m < 10 ? `0${m}` : `${m}`;
        const dd: string = d < 10 ? `0${d}` : `${d}`;
        this.repayDate = `${value.getFullYear()}-${mm}-${dd}`;
      }
    });
  }

  private async saveRepayment(): Promise<void> {
    if (this.repaySaving) {
      return;
    }
    const amountOk: boolean = /^\d+(\.\d{1,2})?$/.test(this.repayAmountText);
    if (!amountOk) {
      this.repayError = '金额格式不对，示例：200 或 200.5';
      return;
    }
    const cents: number = yuanToCents(parseFloat(this.repayAmountText));
    if (cents <= 0) {
      this.repayError = '金额至少 0.01 元';
      return;
    }
    this.repaySaving = true;
    this.repayError = '';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await DbManager.getInstance().init(ctx);
      await this.repayDao.insertRepayment(this.loanId, cents, this.repayDate, this.repayNote.trim());
      promptAction.showToast({ message: '已记一笔还款' });
      this.showPanel = false;
      this.repayAmountText = '';
      this.repayNote = '';
      this.repayDate = todayText();
      await this.loadData();
    } catch (e) {
      this.repayError = `保存失败: ${(e as Error).message}`;
    } finally {
      this.repaySaving = false;
    }
  }

  private confirmDeleteRepay(r: Repayment): void {
    AlertDialog.show({
      message: `删除这笔 ¥${centsToYuanText(r.amountCents)} 的还款记录？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.removeRepayment(r.id);
        }
      }
    });
  }

  private async removeRepayment(id: number): Promise<void> {
    try {
      await this.repayDao.deleteRepayment(id);
      promptAction.showToast({ message: '已删除' });
      await this.loadData();
    } catch (e) {
      promptAction.showToast({ message: `删除失败: ${(e as Error).message}` });
    }
  }

  private goEdit(): void {
    const p: Record<string, number> = { 'loanId': this.loanId };
    router.pushUrl({ url: 'pages/AddLoan', params: p });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 顶栏
        Row() {
          Text('←')
            .fontSize(24)
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              router.back();
            })
            .padding(8)
          Text('借款详情')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text('编辑')
            .fontSize(16)
            .fontColor($r('app.color.accent'))
            .padding(8)
            .onClick(() => {
              this.goEdit();
            })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8 })

        if (!this.loaded) {
          LoadingProgress()
            .width(36)
            .height(36)
            .margin({ top: 100 })
        } else if (this.errorMsg !== '') {
          Text(this.errorMsg)
            .fontSize(14)
            .fontColor($r('app.color.danger'))
            .margin({ top: 40 })
        } else if (!this.hasLoan) {
          Text('未找到这条借款')
            .fontSize(15)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 100 })
        } else {
          Scroll() {
            Column() {
              // 借款信息卡
              Column() {
                Row() {
                  Text(this.loan.person)
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                  if (this.loan.amountCents - this.loan.repaidCents <= 0) {
                    Text('已还清')
                      .fontSize(12)
                      .fontColor($r('app.color.success'))
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .borderRadius(10)
                      .backgroundColor($r('app.color.badge_bg'))
                  }
                }
                .width('100%')

                Text(`¥${centsToYuanText(this.loan.amountCents)}`)
                  .fontSize(34)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ top: 10 })

                Progress({ value: Math.min(this.loan.repaidCents, this.loan.amountCents), total: this.loan.amountCents, type: ProgressType.Linear })
                  .width('100%')
                  .height(6)
                  .margin({ top: 14 })
                  .color($r('app.color.success'))

                Row() {
                  Text(`已还 ¥${centsToYuanText(this.loan.repaidCents)}`)
                    .fontSize(13)
                    .fontColor($r('app.color.success'))
                  Text(` · 待收 ¥${centsToYuanText(this.pendingCents())}`)
                    .fontSize(13)
                    .fontColor(this.pendingCents() > 0 ? $r('app.color.danger') : $r('app.color.text_tertiary'))
                  Blank()
                  Text(`借出日期 ${this.loan.loanDate}`)
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
                .margin({ top: 12 })

                if (this.loan.note !== '') {
                  Text(this.loan.note)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .margin({ top: 10 })
                }
              }
              .width('100%')
              .padding(18)
              .borderRadius(16)
              .backgroundColor($r('app.color.bg_card'))
              .alignItems(HorizontalAlign.Start)

              // 还款记录标题
              Row() {
                Text('还款记录')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(this.repayments.length > 0 ? `共 ${this.repayments.length} 笔 · 长按可删除` : '')
                  .fontSize(12)
                  .fontColor($r('app.color.text_quaternary'))
              }
              .width('100%')
              .margin({ top: 22, bottom: 10 })

              if (this.repayments.length === 0) {
                Column() {
                  Text('🧾')
                    .fontSize(36)
                  Text('还没有还款记录')
                    .fontSize(14)
                    .fontColor($r('app.color.text_tertiary'))
                    .margin({ top: 8 })
                  Text('点下方「记一笔还款」开始记录')
                    .fontSize(12)
                    .fontColor($r('app.color.text_quaternary'))
                    .margin({ top: 4 })
                }
                .width('100%')
                .margin({ top: 20 })
              } else {
                ForEach(this.repayments, (r: Repayment) => {
                  Column() {
                    Row() {
                      Text(`+¥${centsToYuanText(r.amountCents)}`)
                        .fontSize(17)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.success'))
                      Blank()
                      Text(r.repayDate)
                        .fontSize(13)
                        .fontColor($r('app.color.text_tertiary'))
                    }
                    .width('100%')

                    if (r.note !== '') {
                      Text(r.note)
                        .fontSize(13)
                        .fontColor($r('app.color.text_tertiary'))
                        .width('100%')
                        .margin({ top: 6 })
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(12)
                  .backgroundColor($r('app.color.bg_card'))
                  .margin({ bottom: 8 })
                  .gesture(LongPressGesture().onAction(() => {
                    this.confirmDeleteRepay(r);
                  }))
                }, (r: Repayment) => r.id.toString())
              }
            }
            .width('92%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)

          // 记还款按钮
          Button('记一笔还款')
            .width('92%')
            .height(48)
            .fontSize(17)
            .backgroundColor($r('app.color.accent'))
            .margin({ top: 12, bottom: 24 })
            .onClick(() => {
              this.showPanel = true;
            })
        }
      }
      .width('100%')
      .height('100%')

      // 遮罩
      if (this.showPanel) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.35)')
          .onClick(() => {
            this.showPanel = false;
          })
      }

      // 记还款面板
      if (this.showPanel) {
        Column({ space: 14 }) {
          Row() {
            Text('记一笔还款')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Text('✕')
              .fontSize(18)
              .fontColor($r('app.color.text_tertiary'))
              .padding(6)
              .onClick(() => {
                this.showPanel = false;
              })
          }
          .width('100%')

          TextInput({ placeholder: '还款金额，如 200 或 200.5', text: this.repayAmountText })
            .type(InputType.NUMBER_DECIMAL)
            .onChange((v: string) => {
              this.repayAmountText = v;
            })
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .backgroundColor($r('app.color.bg_input'))
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .width('100%')

          Row() {
            Text('还款日期')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(this.repayDate)
              .fontSize(16)
              .fontColor($r('app.color.accent'))
            Text(' 📅')
              .fontSize(14)
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_input'))
          .onClick(() => {
            this.pickRepayDate();
          })

          TextArea({ placeholder: '备注（选填）', text: this.repayNote })
            .onChange((v: string) => {
              this.repayNote = v;
            })
            .fontSize(15)
            .height(64)
            .backgroundColor($r('app.color.bg_input'))
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .width('100%')

          if (this.repayError !== '') {
            Text(this.repayError)
              .fontSize(13)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }

          Button(this.repaySaving ? '保存中…' : '保存还款')
            .width('100%')
            .height(46)
            .fontSize(16)
            .enabled(!this.repaySaving)
            .onClick(() => {
              this.saveRepayment();
            })
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius({ topLeft: 16, topRight: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
