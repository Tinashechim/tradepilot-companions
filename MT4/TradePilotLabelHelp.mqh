// Short explanations for panel labels.
string TP_LabelHelp(string name,string text)
{
 if(name=="TradePilot_TITLE")return "TradePilot helps you size, measure and manage trades on this chart.";
 if(name=="TradePilot_SUBTITLE")return "Created by Tinashe Chimanikire.";
 if(name=="TradePilot_DESCRIPTION")return "Tools for planning trades and managing your daily baskets.";
 if(StringFind(name,"TPM_SL_DIST")>=0)return "Distance from the entry price to the measuring stop loss.";
 if(StringFind(name,"TPM_TP_DIST")>=0)return "Distance from the entry price to the measuring take profit.";
 if(StringFind(name,"TPM_RR")>=0)return "Potential reward compared with risk. For example, 1:2 means aiming to gain twice what you risk.";
 if(StringFind(name,"TPM_RETURN")>=0)return "Potential profit at the measuring take profit, based on the risk amount you entered.";
 if(StringFind(name,"TPM_NOTE")>=0)return "Explains whether the measurement is ready and whether the stop and take profit are on the expected sides of entry.";
 if(StringFind(name,"TradePilot_LIMIT_TITLE")>=0)return "Daily loss protection stops new TradePilot trades when the saved daily loss limit is reached.";
 if(StringFind(name,"TradePilot_LIMIT_MODE_LABEL")>=0)return "Choose whether to enter your daily loss limit as a percentage or money amount.";
 if(StringFind(name,"TradePilot_LIMIT_LABEL")>=0)return "The maximum daily loss you allow before TradePilot stops opening new trades.";
 if(StringFind(name,"TradePilot_LIMIT_REMAIN")>=0)return "How much of your daily loss allowance is still available.";
 if(StringFind(name,"TradePilot_DAILY_MODE_LABEL")>=0)return "Choose Cash, Percentage or a risk-to-reward ratio for today's target.";
 if(StringFind(name,"TradePilot_DAILY_TARGET_LABEL")>=0)return "The profit target you want this daily basket to reach.";
 if(StringFind(name,"TradePilot_DAILY_EQUIVALENT")>=0)return "Your daily target shown as a money amount.";
 if(StringFind(name,"TradePilot_TARGET_OTHER")>=0)return "The same remaining target shown in another mode.";
 if(StringFind(name,"TradePilot_TARGET_UNIT")>=0)return "The unit used for this target, such as your account currency or a percentage.";
 if(StringFind(name,"TradePilot_TP_VALUE_LABEL")>=0)return "How much more this basket needs to earn to reach its target.";
 if(StringFind(name,"TradePilot_BASKET_COSTS")>=0)return "Commission charged for this basket. Credits reduce the cost.";
 if(StringFind(name,"TradePilot_BASKET_GROSS")>=0)return "An estimate of the target before commission, swap and spread costs. These costs are not charged twice.";
 if(StringFind(name,"TradePilot_CALCULATED")>=0)return "The suggested lot size for the risk and stop loss you entered.";
 if(StringFind(name,"TradePilot_FLOATING_EQUIVALENTS")>=0)return "The same open-trade profit or loss shown as money, percentage or ratio.";
 if(StringFind(name,"TradePilot_SIZER_TITLE")>=0)return "Work out a lot size from your risk, stop loss and available margin.";
 if(StringFind(name,"POSITIONS")>=0)return "How many trades are still open in this basket.";
 if(StringFind(name,"COMMISSION")>=0)return "The fee your broker charges for these trades.";
 if(StringFind(name,"SWAP")>=0)return "What your broker adds or charges for keeping trades open overnight.";
 if(StringFind(name,"SPREAD")>=0)return "The difference between the current buy and sell prices.";
 if(StringFind(name,"MARGIN")>=0)return "Money your broker needs to keep this trade open. Green means the checked size fits your available margin.";
 if(StringFind(name,"BROKER_MAX")>=0)return "The largest lot size your broker allows for this symbol. Your risk and available money may limit you to less.";
 if(StringFind(name,"SIZE")>=0)return "The suggested lot size for your stop loss and risk. Broker limits and available margin can make it smaller.";
 if(StringFind(name,"CARRY")>=0)return "Trades still open from earlier days. Each basket keeps its own date, target and progress.";
 if(StringFind(name,"REMAINING")>=0)return "How much more this basket needs to earn to reach its target.";
 if(StringFind(name,"TARGET_VALUE")>=0)return "How much more this basket needs to earn to reach its target.";
 if(StringFind(name,"CLOSED")>=0)return "Profit or loss from trades that have already closed in this period.";
 if(StringFind(name,"PROFIT")>=0)return "How much the open trades in this basket are currently making or losing.";
 if(StringFind(name,"PL_")>=0)return "How much this basket is making or losing.";
 if(StringFind(name,"RISK_MODE")>=0)return "Choose whether to enter your risk as a percentage or a money amount.";
 if(StringFind(name,"RISK")>=0)return "How much you plan to risk if the trade reaches your stop loss.";
 if(StringFind(name,"SL_")>=0)return "The planned stop-loss price. Spread ON adjusts this planned price, not the stops on existing trades.";
 if(StringFind(name,"ENTRY")>=0)return "The price where you plan to enter this trade.";
 if(StringFind(name,"SYMBOL")>=0)return "The instrument shown on this chart, using your broker's exact name.";
 if(StringFind(name,"STATUS")>=0)return "Shows this panel's current progress or what is stopping it.";
 if(StringFind(name,"DAILY")>=0)return "Today's target and results. Press Update to save changes.";
 if(StringFind(name,"SCALE")>=0)return "Make the panel larger or smaller to fit your chart.";
 if(StringFind(name,"TPM_")>=0)return "Measure the planned trade on this chart without placing an order.";
 return "Help for "+text+": this value belongs to the account and chart you are viewing.";
}

// Measure the actual Windows text size before fitting the three header rows.
int TP_HeaderFont(string text,int requested,int width,int height)
{
 int fitted=requested;
 for(;fitted>4;fitted--) {
  uint measured_width=0,measured_height=0;
  if(!TextSetFont("Arial",-10*fitted,0) || !TextGetSize(text,measured_width,measured_height))break;
  if(measured_width<=(uint)width && measured_height<=(uint)height)break;
 }
 return fitted;
}
