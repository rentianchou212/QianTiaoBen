// 人员详情页：某人的借款汇总 + 该人全部借款记录
// 交互：点借款记录进借款详情（记还款/编辑）；长按借款删除这一笔；底部按钮给 TA 再记一笔
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { DbManager } from '../database/DbManager';
import { LoanDao } from '../database/LoanDao';
import { LoanSummary, centsToYuanText } from '../model/LoanModels';

@Entry
@Component
struct PersonDetail {
  @State person: string = '';
  @State loans: LoanSummary[] = [];
  @State loaded: boolean = false;
  @State errorMsg: string = '';

  private loanDao: LoanDao = new LoanDao();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params) {
      const pn: string = params['person'];
      if (typeof pn === 'string' && pn.length > 0) {
        this.person = pn;
        this.loadData();
        return;
      }
    }
    this.errorMsg = '参数错误';
    this.loaded = true;
  }

  // 从借款详情/编辑页返回时刷新
  onPageShow(): void {
    if (this.person.length > 0) {
      this.loadData();
    }
  }

  // 汇总：总借出（分）
  private totalLentCents(): number {
    let sum: number = 0;
    for (const s of this.loans) {
      sum += s.amountCents;
    }
    return sum;
  }

  // 汇总：已还（分），多还的部分不计入
  private totalRepaidCents(): number {
    let sum: number = 0;
    for (const s of this.loans) {
      sum += Math.min(s.repaidCents, s.amountCents);
    }
    return sum;
  }

  // 待收（分），不小于 0
  private pendingCents(): number {
    return Math.max(0, this.totalLentCents() - this.totalRepaidCents());
  }

  private async loadData(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await DbManager.getInstance().init(ctx);
      this.loans = await this.loanDao.getSummariesByPerson(this.person);
      this.loaded = true;
      this.errorMsg = '';
    } catch (e) {
      this.errorMsg = `加载失败: ${(e as Error).message}`;
      this.loaded = true;
    }
  }

  private confirmDeleteLoan(s: LoanSummary): void {
    AlertDialog.show({
      message: `删除「${s.person}」${s.loanDate}借出 ¥${centsToYuanText(s.amountCents)} 这笔借款？\n其还款记录会一并删除。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.removeLoan(s.id);
        }
      }
    });
  }

  private async removeLoan(id: number): Promise<void> {
    try {
      await this.loanDao.deleteLoan(id);
      promptAction.showToast({ message: '已删除' });
      await this.loadData();
    } catch (e) {
      promptAction.showToast({ message: `删除失败: ${(e as Error).message}` });
    }
  }

  private addLoanForPerson(): void {
    const p: Record<string, string> = { 'person': this.person };
    router.pushUrl({ url: 'pages/AddLoan', params: p });
  }

  build() {
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
        Text('借款人详情')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('  ')
          .fontSize(24)
          .padding(8)
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
      } else {
        Scroll() {
          Column() {
            // 汇总卡
            Column() {
              Row() {
                Text(this.person)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.pendingCents() <= 0 && this.loans.length > 0) {
                  Text('已还清')
                    .fontSize(12)
                    .fontColor($r('app.color.success'))
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .borderRadius(10)
                    .backgroundColor($r('app.color.badge_bg'))
                }
              }
              .width('100%')

              Text(`¥${centsToYuanText(this.totalLentCents())}`)
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 10 })

              Progress({ value: Math.min(this.totalRepaidCents(), this.totalLentCents()), total: this.totalLentCents(), type: ProgressType.Linear })
                .width('100%')
                .height(6)
                .margin({ top: 14 })
                .color($r('app.color.success'))

              Row() {
                Text(`已还 ¥${centsToYuanText(this.totalRepaidCents())}`)
                  .fontSize(13)
                  .fontColor($r('app.color.success'))
                Text(` · 待收 ¥${centsToYuanText(this.pendingCents())}`)
                  .fontSize(13)
                  .fontColor(this.pendingCents() > 0 ? $r('app.color.danger') : $r('app.color.text_tertiary'))
                Blank()
                Text(`${this.loans.length} 笔借款`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('100%')
            .padding(18)
            .borderRadius(16)
            .backgroundColor($r('app.color.bg_card'))
            .alignItems(HorizontalAlign.Start)

            // 借款记录标题
            Row() {
              Text('借款记录')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(this.loans.length > 0 ? `共 ${this.loans.length} 笔 · 长按可删除` : '')
                .fontSize(12)
                .fontColor($r('app.color.text_quaternary'))
            }
            .width('100%')
            .margin({ top: 22, bottom: 10 })

            if (this.loans.length === 0) {
              Column() {
                Text('🧾')
                  .fontSize(36)
                Text('没有借款记录')
                  .fontSize(14)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 8 })
              }
              .width('100%')
              .margin({ top: 20 })
            } else {
              ForEach(this.loans, (s: LoanSummary) => {
                Column() {
                  Row() {
                    Text(`¥${centsToYuanText(s.amountCents)}`)
                      .fontSize(17)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                    if (s.amountCents - s.repaidCents <= 0) {
                      Text('已还清')
                        .fontSize(12)
                        .fontColor($r('app.color.success'))
                        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                        .borderRadius(10)
                        .backgroundColor($r('app.color.badge_bg'))
                        .margin({ left: 8 })
                    }
                    Blank()
                    Text(s.loanDate)
                      .fontSize(13)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                  .width('100%')

                  Text(`已还 ¥${centsToYuanText(s.repaidCents)} · 待收 ¥${centsToYuanText(Math.max(0, s.amountCents - s.repaidCents))}`)
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                    .margin({ top: 6 })

                  if (s.note !== '') {
                    Text(s.note)
                      .fontSize(13)
                      .fontColor($r('app.color.text_quaternary'))
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
                .onClick(() => {
                  const p: Record<string, number> = { 'loanId': s.id };
                  router.pushUrl({ url: 'pages/LoanDetail', params: p });
                })
                .gesture(LongPressGesture().onAction(() => {
                  this.confirmDeleteLoan(s);
                }))
              }, (s: LoanSummary) => `${s.id}_${s.amountCents}_${s.repaidCents}`)
            }
          }
          .width('92%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        // 底部按钮：给 TA 再记一笔（姓名自动带过去）
        Button('再记一笔借款')
          .width('92%')
          .height(48)
          .fontSize(17)
          .backgroundColor($r('app.color.accent'))
          .margin({ top: 12, bottom: 24 })
          .onClick(() => {
            this.addLoanForPerson();
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
