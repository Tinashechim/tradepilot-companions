// TradePilot local desktop bridge. No network listeners or DLL imports.
#ifndef TRADEPILOT_LOCAL_BRIDGE
#define TRADEPILOT_LOCAL_BRIDGE

input bool TP_LocalBridge = false; // Enable only after registering this account in the desktop app
input string TP_AccountId = "";    // Desktop-generated connection ID
input string TP_BridgeToken = "";  // Desktop-generated connection token
input bool TP_IsSlave = false; // Follower account (managed by TradePilot)
input double TP_MaxRiskPercent = 100.0;
input int TP_SlippagePoints = 10;

string tp_month="", tp_prefix="";
double tp_opening=0, tp_closed=0, tp_float=0, tp_tier=0;
double tp_closed_start=0, tp_float_start=0;
bool tp_reached=false, tp_paid=false, tp_enabled=false;
datetime tp_lease=0;
long tp_offset=0;
long tp_reset_revision=0;
datetime tp_last_server=0;
bool tp_owner=false;
bool tp_clock_ready=false;
string tp_last_command_check="";
void TP_CommandCheck(string detail)
{
   if(detail==tp_last_command_check) return;
   tp_last_command_check=detail;
   Print("TradePilot command check: ",detail);
}

string TP_Path(string suffix) { return "TradePilotLocal\\"+TP_AccountId+suffix; }
string TP_Num(double n) { return DoubleToString(n,8); }
string TP_Int(long n) { return IntegerToString(n); }

double TP_Balance()
{
#ifdef __MQL5__
   return AccountInfoDouble(ACCOUNT_BALANCE);
#else
   return AccountBalance();
#endif
}
string TP_Login()
{
#ifdef __MQL5__
   return TP_Int(AccountInfoInteger(ACCOUNT_LOGIN));
#else
   return IntegerToString(AccountNumber());
#endif
}
string TP_Server()
{
#ifdef __MQL5__
   return AccountInfoString(ACCOUNT_SERVER);
#else
   return AccountServer();
#endif
}
datetime TP_ServerNow()
{
   datetime broker=TimeCurrent();
   if(broker!=tp_last_server && TerminalInfoInteger(TERMINAL_CONNECTED) && MathAbs((double)((long)broker-(long)TimeGMT()))<=14*3600)
   {
      tp_offset=(long)broker-(long)TimeGMT();
      tp_last_server=broker;
      tp_clock_ready=true;
      GlobalVariableSet(tp_prefix+"OFFSET",(double)tp_offset);
   }
   return (datetime)((long)TimeGMT()+tp_offset);
}
string TP_Month(datetime now)
{
   MqlDateTime p; TimeToStruct(now,p);
   return StringFormat("%04d-%02d",p.year,p.mon);
}
datetime TP_MonthStart(datetime now)
{
   MqlDateTime p; TimeToStruct(now,p);
   p.day=1; p.hour=0; p.min=0; p.sec=0;
   return StructToTime(p);
}

bool TP_TradingPermission()
{
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}
void TP_PermissionDetails(string platform)
{
   string text="PERMISSIONS\t"+TP_BridgeToken+"\t"+TP_AccountId+"\t"+TP_Login()+"\t"+TP_Server()+"\t"+platform+"\t"+TP_Int(TimeGMT())+"\t"+
      (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"1":"0")+"\t"+(MQLInfoInteger(MQL_TRADE_ALLOWED)?"1":"0")+"\t"+
      (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)?"1":"0")+"\t"+(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)?"1":"0")+"\r\n";
   TP_Atomic(".permissions.tsv",text);
}
bool TP_Read(string suffix,string &parts[])
{
   int f=FileOpen(TP_Path(suffix),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(f==INVALID_HANDLE)
   {
      if(suffix==".command.tsv")
         TP_CommandCheck("Command file cannot be read; error "+IntegerToString(GetLastError()));
      return false;
   }
   string row=FileReadString(f); FileClose(f);
   int count=StringSplit(row,9,parts);
   if(suffix==".command.tsv" && count<=0) TP_CommandCheck("Command file contains no readable fields");
   return count>0;
}
void TP_Atomic(string suffix,string text)
{
   int f=FileOpen(TP_Path(suffix+".tmp"),FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON,0,CP_UTF8);
   if(f==INVALID_HANDLE) return;
   FileWriteString(f,text); FileFlush(f); FileClose(f);
   FileMove(TP_Path(suffix+".tmp"),FILE_COMMON,TP_Path(suffix),FILE_COMMON|FILE_REWRITE);
}
void TP_ConnectionPing()
{
   string fields[];
   if(!TP_Read(".ping.tsv",fields) || ArraySize(fields)!=4) return;
   if(fields[0]!=TP_BridgeToken || fields[1]!=TP_AccountId || StringLen(fields[2])!=32) return;
   long expiry=(long)StringToInteger(fields[3]);
   if(expiry<(long)TimeGMT() || expiry>(long)TimeGMT()+20) return;
#ifdef __MQL5__
   string platform="MT5";
#else
   string platform="MT4";
#endif
   TP_Atomic(".pong.tsv",TP_BridgeToken+"\t"+TP_AccountId+"\t"+fields[2]+"\t"+TP_Login()+"\t"+AccountInfoString(ACCOUNT_SERVER)+"\t"+platform+"\r\n");
}
void TP_Ack(string command,string status,string detail)
{
   TP_Atomic(".ack",TP_BridgeToken+"\t"+command+"\t"+status+"\t"+detail+"\r\n");
}
string TP_Comment(string source) { return "TP#"+source; }
string TP_Source(string comment)
{
   if(StringFind(comment,"TP#")!=0) return "";
   string source="";
   for(int i=3;i<StringLen(comment);i++)
   {
      ushort c=StringGetCharacter(comment,i);
      if(c<48 || c>57) break;
      source+=StringSubstr(comment,i,1);
   }
   return source;
}

// Persist intended master risk before its signal is exported. This remains
// unchanged when the stop is trailed or account balance subsequently changes.
void TP_RecordRisk(long identifier,double cash_risk,double balance)
{
   if(!TP_LocalBridge || TP_IsSlave || balance<=0 || identifier<=0) return;
   GlobalVariableSet("TPRisk_"+TP_AccountId+"_"+TP_Int(identifier),100.0*cash_risk/balance);
   GlobalVariablesFlush();
}
double TP_Risk(long identifier,string symbol,int side,double lots,double entry,double stop)
{
   string key="TPRisk_"+TP_AccountId+"_"+TP_Int(identifier);
   if(GlobalVariableCheck(key)) return GlobalVariableGet(key);
   // Existing or external master orders without captured sizing data are not signals.
   return 0.0;
}


// History readiness is reported by the backend; no admin confirmation input.
bool TP_HistoryReady()
{
#ifdef __MQL5__
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   return HistorySelect(0,TP_ServerNow());
#else
   static int previous=-1; static datetime stable=0;
   static bool ready=false, range_reduced=false;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   { previous=-1; stable=0; ready=false; return false; }
   string policy[];
   if(!TP_Read(".history-policy.tsv",policy) || ArraySize(policy)!=3 ||
      policy[0]!=TP_BridgeToken || policy[1]!=TP_AccountId || policy[2]!="7")
   { previous=-1; stable=0; ready=false; return false; }
   // MT4 has no download-complete API. Settle the initial broker-available
   // history after All History was configured. Normal new exits do not block
   // the next copy. A reduced range fails closed until re-prepared/restarted.
   int count=OrdersHistoryTotal();
   if(range_reduced) return false;
   if(ready)
   {
      if(count<previous) { range_reduced=true; ready=false; return false; }
      previous=count; return true;
   }
   if(count!=previous) { previous=count; stable=TimeGMT(); return false; }
   ready=stable>0 && TimeGMT()-stable>=30;
   return ready;
#endif
}

// Read-only broker execution history for PDF statements. Never issues orders.

#ifdef __MQL5__
string TP_ExitReason(ulong ticket,string kind)
{
 if(kind=="ENTRY")return "ENTRY";
 long reason=HistoryDealGetInteger(ticket,DEAL_REASON);
 if(reason==DEAL_REASON_SL)return "STOP_LOSS";
 if(reason==DEAL_REASON_TP)return "TAKE_PROFIT";
 if(reason==DEAL_REASON_SO)return "STOP_OUT";
 if(reason==DEAL_REASON_CLIENT || reason==DEAL_REASON_MOBILE || reason==DEAL_REASON_WEB)return "USER";
 if(reason==DEAL_REASON_EXPERT)return "EXPERT";
 return "BROKER_CODE_"+IntegerToString((int)reason);
}

string TP_DealExecution(ulong ticket,string kind)
{
 if(kind=="EXIT") return "FOLLOW_ENTRY";
 if(kind=="REVERSAL") return "PENDING";
 string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
 if(StringFind(comment,"TradePilot pending")==0) return "SYSTEM_MANUAL";
 if(StringFind(comment,"TP-MANUAL")==0 || comment=="TradePilot") return "SYSTEM_MANUAL";
 long reason=HistoryDealGetInteger(ticket,DEAL_REASON);
 if(reason==DEAL_REASON_CLIENT || reason==DEAL_REASON_MOBILE || reason==DEAL_REASON_WEB) return "MANUAL";
 if(reason==DEAL_REASON_EXPERT) return "SYSTEM";
 return "PENDING";
}
#else
string TP_OrderExecution()
{
 string comment=OrderComment();
 if(StringFind(comment,"TP#")==0) return "SYSTEM";
 if(StringFind(comment,"TradePilot pending")==0) return "SYSTEM_MANUAL";
 if(StringFind(comment,"TP-MANUAL")==0 || comment=="TradePilot") return "SYSTEM_MANUAL";
 return OrderMagicNumber()!=0 ? "SYSTEM" : "MANUAL";
}
#endif
void TP_StatementHistory(datetime now)
{
   static datetime last=0;
   if(last>0 && now>=last && now-last<30) return;
   last=now;
   string rows=""; int count=0;
#ifdef __MQL5__
   string currency=AccountInfoString(ACCOUNT_CURRENCY),platform="MT5";
   bool complete=TP_HistoryReady();
   if(!HistorySelect(0,now)) return;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      long type=HistoryDealGetInteger(ticket,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      string kind=entry==DEAL_ENTRY_IN ? "ENTRY" : entry==DEAL_ENTRY_INOUT ? "REVERSAL" : "EXIT";
      datetime stamp=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      string when=TimeToString(stamp,TIME_DATE|TIME_SECONDS);
      double price=HistoryDealGetDouble(ticket,DEAL_PRICE);
      rows+="RECORD\t"+TP_Int((long)ticket)+"\t"+TP_Int(HistoryDealGetInteger(ticket,DEAL_POSITION_ID))+"\t"+
         HistoryDealGetString(ticket,DEAL_SYMBOL)+"\t"+kind+"\t"+
         (kind=="EXIT" ? "" : when)+"\t"+(kind=="ENTRY" ? "" : when)+"\t"+
         TP_Num(HistoryDealGetDouble(ticket,DEAL_VOLUME))+"\t"+TP_Num(kind=="EXIT" ? 0 : price)+"\t"+
         TP_Num(kind=="ENTRY" ? 0 : price)+"\t"+TP_Num(HistoryDealGetDouble(ticket,DEAL_PROFIT))+"\t"+
         TP_Num(HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_FEE))+"\t"+
         TP_Num(HistoryDealGetDouble(ticket,DEAL_SWAP))+"\t"+(type==DEAL_TYPE_BUY ? "BUY" : "SELL")+"\t"+TP_DealExecution(ticket,kind)+"\t"+TP_ExitReason(ticket,kind)+"\r\n";
      count++;
   }
#else
   string currency=AccountCurrency(),platform="MT4";
   bool complete=TP_HistoryReady();
   for(int i=0;i<OrdersHistoryTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      rows+="RECORD\t"+TP_Int(OrderTicket())+"\t"+TP_Int(OrderTicket())+"\t"+OrderSymbol()+"\tCLOSED\t"+
         TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS)+"\t"+TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS)+"\t"+
         TP_Num(OrderLots())+"\t"+TP_Num(OrderOpenPrice())+"\t"+TP_Num(OrderClosePrice())+"\t"+
         TP_Num(OrderProfit())+"\t"+TP_Num(OrderCommission())+"\t"+TP_Num(OrderSwap())+"\t"+
         (OrderType()==OP_BUY ? "BUY" : "SELL")+"\t"+TP_OrderExecution()+"\tNOT_SUPPLIED_BY_MT4\r\n";
      count++;
   }
   for(int i=0;i<OrdersTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      rows+="RECORD\tOPEN-"+TP_Int(OrderTicket())+"\t"+TP_Int(OrderTicket())+"\t"+OrderSymbol()+"\tENTRY\t"+
         TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS)+"\t\t"+TP_Num(OrderLots())+"\t"+TP_Num(OrderOpenPrice())+
         "\t0\t0\t"+TP_Num(OrderCommission())+"\t0\t"+(OrderType()==OP_BUY ? "BUY" : "SELL")+"\t"+TP_OrderExecution()+"\tENTRY\r\n";
      count++;
   }
#endif
   string meta="HISTORY\t"+TP_AccountId+"\t"+TP_Login()+"\t"+TP_Server()+"\t"+platform+"\t"+
      TimeToString(now,TIME_DATE|TIME_SECONDS)+"\t"+(complete ? "1" : "0")+"\t"+TP_Int(TimeGMT())+"\t3\t"+currency+"\t"+TP_BridgeToken+"\r\n";
   TP_Atomic(".history.tsv",meta+rows+"END\t"+IntegerToString(count)+"\r\n");
}

void TP_Accounting(datetime start)
{
   tp_closed=0; tp_float=0;
   double changes=0;
#ifdef __MQL5__
   if(!HistorySelect(start,TP_ServerNow())) { tp_opening=0; return; }
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong t=HistoryDealGetTicket(i);
      double value=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_COMMISSION)+
                   HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_FEE);
      long type=HistoryDealGetInteger(t,DEAL_TYPE);
      // Credit changes do not change balance and are never investment return.
      if(type!=DEAL_TYPE_CREDIT) changes+=value;
      if(type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL || type==DEAL_TYPE_COMMISSION ||
         type==DEAL_TYPE_COMMISSION_DAILY || type==DEAL_TYPE_COMMISSION_MONTHLY)
         tp_closed+=value;
   }
   for(int i=0;i<PositionsTotal();i++)
      if(PositionGetTicket(i)>0) tp_float+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
#else
   for(int i=0;i<OrdersHistoryTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) || OrderCloseTime()<start) continue;
      double value=OrderProfit()+OrderSwap()+OrderCommission();
      if(OrderType()!=7) changes+=value; // MT4 credit is not balance.
      if(OrderType()==OP_BUY || OrderType()==OP_SELL) tp_closed+=value;
   }
   for(int i=0;i<OrdersTotal();i++)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && (OrderType()==OP_BUY || OrderType()==OP_SELL))
         tp_float+=OrderProfit()+OrderSwap()+OrderCommission();
#endif
   // The desktop captures current balance and profit offsets on activation.
   // Never infer a target baseline from deposits or earlier monthly trades.
   string key=tp_prefix+tp_month+"_CURRENT_BASE";
   tp_opening=0; tp_closed_start=0; tp_float_start=0;
   if(GlobalVariableCheck(key) && GlobalVariableCheck(key+"_C") && GlobalVariableCheck(key+"_F"))
   {
      tp_opening=GlobalVariableGet(key);
      tp_closed_start=GlobalVariableGet(key+"_C");
      tp_float_start=GlobalVariableGet(key+"_F");
   }
}

int TP_Positions()
{
#ifdef __MQL5__
   return PositionsTotal();
#else
   int n=0;
   for(int i=0;i<OrdersTotal();i++) if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderType()<=OP_SELL) n++;
   return n;
#endif
}
int TP_Pending()
{
#ifdef __MQL5__
   return OrdersTotal();
#else
   return OrdersTotal()-TP_Positions();
#endif
}

bool TP_CloseTicket(ulong ticket,double fraction=1.0)
{
#ifdef __MQL5__
   if(!PositionSelectByTicket(ticket)) return true;
   string symbol=PositionGetString(POSITION_SYMBOL);
   double volume=PositionGetDouble(POSITION_VOLUME);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double close_volume=NormalizeDouble(MathFloor(volume*fraction/step+1e-8)*step,8);
   if(close_volume<=0) return true;
   CTrade broker;
   broker.SetDeviationInPoints(TP_SlippagePoints);
   broker.SetTypeFillingBySymbol(symbol);
   bool result=close_volume>=volume ? broker.PositionClose(ticket) : broker.PositionClosePartial(ticket,close_volume);
   return result && (broker.ResultRetcode()==TRADE_RETCODE_DONE || broker.ResultRetcode()==TRADE_RETCODE_DONE_PARTIAL);
#else
   if(!OrderSelect((int)ticket,SELECT_BY_TICKET) || OrderCloseTime()>0) return true;
   string symbol=OrderSymbol();
   double step=MarketInfo(symbol,MODE_LOTSTEP);
   double volume=NormalizeDouble(MathFloor(OrderLots()*fraction/step+1e-8)*step,8);
   if(volume<=0) return true;
   return OrderClose((int)ticket,volume,MarketInfo(symbol,OrderType()==OP_BUY ? MODE_BID : MODE_ASK),TP_SlippagePoints,clrNONE);
#endif
}

// Tier closure deliberately applies to ALL trades and pending orders on a slave.
// It remains latched even if floating profit falls while some closes are rejected.
void TP_CloseAll()
{
#ifdef __MQL5__
   for(int i=PositionsTotal()-1;i>=0;i--) { ulong t=PositionGetTicket(i); if(t>0) TP_CloseTicket(t); }
   CTrade broker;
   for(int i=OrdersTotal()-1;i>=0;i--) { ulong t=OrderGetTicket(i); if(t>0) broker.OrderDelete(t); }
#else
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int ticket=OrderTicket();
      if(OrderType()<=OP_SELL) TP_CloseTicket((ulong)ticket);
      else if(!OrderDelete(ticket,clrNONE)) Print("TradePilot: pending order removal will retry ",ticket);
   }
#endif
}

bool TP_FindCopy(string source,ulong &ticket)
{
#ifdef __MQL5__
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(t>0 && TP_Source(PositionGetString(POSITION_COMMENT))==source) { ticket=t; return true; }
   }
#else
   for(int i=0;i<OrdersTotal();i++)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && TP_Source(OrderComment())==source) { ticket=(ulong)OrderTicket(); return true; }
#endif
   return false;
}

bool TP_UpdateCopy(string source,double sl,double tp,double ratio,string command)
{
   ulong ticket=0;
   if(!TP_FindCopy(source,ticket)) return true;
   string partial_key=tp_prefix+"PART_"+command;
   // Persist the partial-close claim first; never repeat a partial close after a crash.
   if(ratio<0.999999 && !GlobalVariableCheck(partial_key))
   {
      GlobalVariableSet(partial_key,1); GlobalVariablesFlush();
      if(!TP_CloseTicket(ticket,1.0-ratio)) { GlobalVariableDel(partial_key); return false; }
   }
   if(!TP_FindCopy(source,ticket)) return true;
#ifdef __MQL5__
   if(PositionGetDouble(POSITION_SL)==sl && PositionGetDouble(POSITION_TP)==tp) return true;
   CTrade broker; broker.SetTypeFillingBySymbol(PositionGetString(POSITION_SYMBOL));
   return broker.PositionModify(ticket,sl,tp) && broker.ResultRetcode()==TRADE_RETCODE_DONE;
#else
   if(OrderStopLoss()==sl && OrderTakeProfit()==tp) return true;
   return OrderModify((int)ticket,OrderOpenPrice(),sl,tp,0,clrNONE);
#endif
}


// Estimate per symbol from up to 30 recent fully closed trades. Never infer free
// trading from absent commission records. Three positive samples are required.
string tp_cost_account="";
string tp_cost_symbols[];
double tp_cost_values[];
datetime tp_cost_checked[];
double TP_Commission(string symbol)
{
   string account=TP_Login()+"|"+TP_Server();
   if(tp_cost_account!=account)
   {
      ArrayResize(tp_cost_symbols,0); ArrayResize(tp_cost_values,0); ArrayResize(tp_cost_checked,0); tp_cost_account=account;
   }
   int slot=-1;
   for(int c=0;c<ArraySize(tp_cost_symbols);c++) if(tp_cost_symbols[c]==symbol) { slot=c; break; }
   if(slot>=0 && TimeLocal()-tp_cost_checked[slot]<60) return tp_cost_values[slot];
   double maximum=0; int samples=0;
   datetime since=TimeCurrent()-90*86400;
#ifdef __MQL5__
   ulong ids[];
   if(HistorySelect(since,TimeCurrent()))
   {
      for(int i=HistoryDealsTotal()-1;i>=0 && ArraySize(ids)<30;i--)
      {
         ulong ticket=HistoryDealGetTicket(i);
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=symbol) continue;
         long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
         ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
         bool seen=false;
         for(int j=0;j<ArraySize(ids);j++) if(ids[j]==id) seen=true;
         if(!seen) { int n=ArraySize(ids); ArrayResize(ids,n+1); ids[n]=id; }
      }
   }
   for(int k=0;k<ArraySize(ids);k++)
   {
      bool open=false;
      for(int q=0;q<PositionsTotal();q++)
      {
         if(PositionGetTicket(q)>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==ids[k]) open=true;
      }
      if(open || !HistorySelectByPosition(ids[k])) continue;
      double incoming=0,outgoing=0,cost=0; bool valid=true;
      for(int d=0;d<HistoryDealsTotal();d++)
      {
         ulong ticket=HistoryDealGetTicket(d);
         long type=HistoryDealGetInteger(ticket,DEAL_TYPE);
         if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) { valid=false; continue; }
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=symbol) { valid=false; continue; }
         long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
         double volume=HistoryDealGetDouble(ticket,DEAL_VOLUME);
         if(entry==DEAL_ENTRY_IN) incoming+=volume;
         else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) outgoing+=volume;
         else valid=false;
         cost+=MathAbs(HistoryDealGetDouble(ticket,DEAL_COMMISSION))+MathAbs(HistoryDealGetDouble(ticket,DEAL_FEE));
      }
      if(valid && incoming>0 && MathAbs(incoming-outgoing)<0.00000001 && cost>0)
         { maximum=MathMax(maximum,cost/incoming); samples++; }
   }
#else
   for(int i=OrdersHistoryTotal()-1;i>=0 && samples<30;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) || OrderSymbol()!=symbol || OrderType()>OP_SELL || OrderCloseTime()<since || OrderLots()<=0) continue;
      double cost=MathAbs(OrderCommission());
      if(cost>0) { maximum=MathMax(maximum,cost/OrderLots()); samples++; }
   }
#endif
   double result=samples>=3 ? maximum : -1.0;
   if(slot<0)
   {
      slot=ArraySize(tp_cost_symbols); ArrayResize(tp_cost_symbols,slot+1);
      ArrayResize(tp_cost_values,slot+1); ArrayResize(tp_cost_checked,slot+1);
      tp_cost_symbols[slot]=symbol;
   }
   tp_cost_values[slot]=result; tp_cost_checked[slot]=TimeLocal();
   return result;
}

void TP_Discovery()
{
#ifdef __MQL5__
   string platform="MT5";
#else
   string platform="MT4";
#endif
   string text="DISCOVERY\t"+TP_BridgeToken+"\t"+TP_Login()+"\t"+TP_Server()+"\t"+platform+"\t"+TerminalInfoString(TERMINAL_DATA_PATH)+"\t"+TP_Int(TimeGMT())+"\t"+((TP_TradingPermission()) ? "1" : "0")+"\r\n";
   string seen="|"; long chart=ChartFirst();
   for(int i=0;i<100 && chart>=0;i++)
   {
      string symbol=ChartSymbol(chart);
      if(symbol!="" && StringFind(seen,"|"+symbol+"|")<0)
      {
         seen+=symbol+"|";
         text+="SYMBOL\t"+symbol+"\t"+TP_Num(TP_Commission(symbol))+"\r\n";
      }
      chart=ChartNext(chart);
   }
   TP_Atomic(".discovery",text);
}

bool TP_Open(string source,string symbol,int side,double risk,double sl,double tp,string &detail)
{
   if(!TPDL_EntryAllowed(detail)) return false;
   if(risk<=0 || risk>TP_MaxRiskPercent || sl<=0) { detail="Risk or stop loss is invalid"; return false; }
   ResetLastError();
   if(!SymbolSelect(symbol,true))
   {
      int error=GetLastError();
      detail=error==4301 ? "Symbol not available: "+symbol+" (broker symbol error "+IntegerToString(error)+"); verify exact symbol mapping" : "Could not select requested symbol "+symbol+" (terminal error "+IntegerToString(error)+"). Review this error; symbol absence is not established.";
      return false;
   }
   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick) || tick.ask<=0 || tick.bid<=0 || TP_ServerNow()-tick.time>15)
      { detail="No fresh broker quote"; return false; }
   double entry=side==0 ? tick.ask : tick.bid;
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   long stops=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double distance=side==0 ? tick.bid-sl : sl-tick.ask;
   if(distance<=0 || distance<stops*point) { detail="Follower stop loss invalid at current price"; return false; }
   double loss=0;
#ifdef __MQL5__
   double profit=0,probe=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(probe<=0 || !OrderCalcProfit(side==0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,symbol,probe,entry,sl,profit))
      { detail="Broker risk calculation unavailable"; return false; }
   loss=MathAbs(profit)/probe;
#else
   double size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE), value=MarketInfo(symbol,MODE_TICKVALUE);
   if(size<=0 || value<=0) { detail="Broker tick values unavailable"; return false; }
   loss=MathAbs(entry-sl)/size*value;
#endif
   // Same stop-loss price-risk model as the master position sizer.
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || loss<=0) { detail="Volume specification unavailable"; return false; }
   double volume=NormalizeDouble(MathFloor((TPDL_CapRisk(TP_Balance()*risk/100.0)/loss)/step)*step,8);
   volume=TP_AffordableLots(symbol,side,entry,volume);
   if(volume<0) {detail="Broker margin calculation unavailable";return false;}
   if(volume<minimum) {detail="Below minimum lot or insufficient free margin";return false;}
   double confirmed_margin=0;
   if(!TPDL_EntryAllowed(detail) || !TPDL_AcceptRisk(volume*loss,detail)) return false;
   int checked=TP_CheckMargin(symbol,side,entry,volume,confirmed_margin);
   if(checked!=1) {detail=checked<0 ? "Broker margin calculation unavailable" : "Insufficient free margin";return false;}
#ifdef __MQL5__
   CTrade broker; broker.SetDeviationInPoints(TP_SlippagePoints); broker.SetTypeFillingBySymbol(symbol);
   bool result=side==0 ? broker.Buy(volume,symbol,0,sl,tp,TP_Comment(source)) : broker.Sell(volume,symbol,0,sl,tp,TP_Comment(source));
   bool ok=result && (broker.ResultRetcode()==TRADE_RETCODE_DONE || broker.ResultRetcode()==TRADE_RETCODE_DONE_PARTIAL);
   detail=ok ? "Copied "+DoubleToString(volume,8)+" lots" : broker.ResultRetcodeDescription();
   if(!ok && broker.ResultRetcode()==TRADE_RETCODE_SERVER_DISABLES_AT)
      detail="Broker blocked automated trading (10026). Ask the broker to allow Expert Advisor trading for this account; the local toolbar and F7 switches cannot override a server restriction.";
   else if(!ok && broker.ResultRetcode()==TRADE_RETCODE_CLIENT_DISABLES_AT)
      detail="MT5 blocked automated trading locally (10027). Check Algo Trading and F7 / Common / Allow Algo Trading.";
   return ok;
#else
   int ticket=OrderSend(symbol,side,volume,entry,TP_SlippagePoints,sl,tp,TP_Comment(source),731905,0,clrNONE);
   detail=ticket>0 ? "Copied "+DoubleToString(volume,8)+" lots" : "Broker error "+IntegerToString(GetLastError());
   return ticket>0;
#endif
}

void TP_Command()
{
   string p[];
   if(!TP_Read(".command.tsv",p)) return;
   if(ArraySize(p)!=11) { TP_CommandCheck("Invalid command field count: "+IntegerToString(ArraySize(p))); return; }
   if(p[0]!=TP_BridgeToken) { TP_CommandCheck("Command connection identity mismatch"); return; }
   if((datetime)StringToInteger(p[10])<TimeGMT()) { TP_CommandCheck("Command lease expired"); return; }
   TP_CommandCheck("Authenticated command received: "+p[2]+" #"+p[1]);
   string command=p[1], action=p[2], source=p[3];
   string receipt=tp_prefix+"CMD_"+command;
   double state=GlobalVariableCheck(receipt) ? GlobalVariableGet(receipt) : 0;
   if(state==1) { TP_Ack(command,"OK","Previously completed"); return; }
   if(state==2) { TP_Ack(command,"ERROR","Previously rejected; check activity and terminal journal"); return; }
   if(action=="OPEN")
   {
      ulong existing=0;
      if(TP_FindCopy(source,existing)) { GlobalVariableSet(receipt,1); TP_Ack(command,"OK","Existing copy reconciled"); return; }
      if(state==-1) { TP_Ack(command,"ERROR","Uncertain prior send; inspect broker history, not resent"); return; }
      if(!tp_enabled || !tp_paid || tp_reached || !TP_HistoryReady() || tp_opening<=0 || TimeGMT()>tp_lease)
         { GlobalVariableSet(receipt,2); TP_Ack(command,"ERROR","Entry blocked by account policy"); return; }
      GlobalVariableSet(receipt,-1); GlobalVariablesFlush();
      string detail="";
      bool ok=TP_Open(source,p[4],p[5]=="BUY" ? 0 : 1,StringToDouble(p[6]),StringToDouble(p[7]),StringToDouble(p[8]),detail);
      GlobalVariableSet(receipt,ok ? 1 : 2); GlobalVariablesFlush();
      TP_Ack(command,ok ? "OK" : "ERROR",detail);
   }
   else if(action=="CLOSE" || action=="UPDATE")
   {
      ulong ticket=0;
      bool ok=action=="CLOSE" ? (!TP_FindCopy(source,ticket) || TP_CloseTicket(ticket)) :
         TP_UpdateCopy(source,StringToDouble(p[7]),StringToDouble(p[8]),StringToDouble(p[9]),command);
      if(ok) { GlobalVariableSet(receipt,1); GlobalVariablesFlush(); TP_Ack(command,"OK","Copy management completed"); }
      // Broker-rejected exits remain pending and retry; payment pauses never block exits.
   }
}

void TP_PendingDetails(datetime now)
{
   string rows="";int count=0;
#ifdef __MQL5__
   string platform="MT5";
   for(int i=0;i<OrdersTotal();i++) {
      ulong ticket=OrderGetTicket(i);if(ticket==0) continue;
      int type=(int)OrderGetInteger(ORDER_TYPE);
      if(type<ORDER_TYPE_BUY_LIMIT || type>ORDER_TYPE_SELL_STOP_LIMIT) continue;
      string names[6]={"BUY LIMIT","SELL LIMIT","BUY STOP","SELL STOP","BUY STOP LIMIT","SELL STOP LIMIT"};
      rows+="ORDER\t"+TP_Int((long)ticket)+"\t"+OrderGetString(ORDER_SYMBOL)+"\t"+names[type-ORDER_TYPE_BUY_LIMIT]+"\t"+TP_Num(OrderGetDouble(ORDER_VOLUME_CURRENT))+"\t"+TP_Num(OrderGetDouble(ORDER_PRICE_OPEN))+"\t"+TP_Num(OrderGetDouble(ORDER_SL))+"\t"+TP_Num(OrderGetDouble(ORDER_TP))+"\t"+TP_Int(OrderGetInteger(ORDER_TIME_EXPIRATION))+"\t"+TP_Int(OrderGetInteger(ORDER_TIME_SETUP))+"\r\n";
      count++;
   }
#else
   string platform="MT4";
   for(int i=0;i<OrdersTotal();i++) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderType()<OP_BUYLIMIT || OrderType()>OP_SELLSTOP) continue;
      string names[4]={"BUY LIMIT","SELL LIMIT","BUY STOP","SELL STOP"};
      rows+="ORDER\t"+TP_Int(OrderTicket())+"\t"+OrderSymbol()+"\t"+names[OrderType()-OP_BUYLIMIT]+"\t"+TP_Num(OrderLots())+"\t"+TP_Num(OrderOpenPrice())+"\t"+TP_Num(OrderStopLoss())+"\t"+TP_Num(OrderTakeProfit())+"\t"+TP_Int(OrderExpiration())+"\t"+TP_Int(OrderOpenTime())+"\r\n";
      count++;
   }
#endif
   TP_Atomic(".pending.tsv","META\t"+TP_BridgeToken+"\t"+TP_AccountId+"\t"+TP_Login()+"\t"+TP_Server()+"\t"+platform+"\t"+TimeToString(now,TIME_DATE|TIME_SECONDS)+"\r\n"+rows+"END\t"+IntegerToString(count)+"\r\n");
}

string TP_Trades(int &count)
{
   string rows=""; count=0;
#ifdef __MQL5__
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      long id=PositionGetInteger(POSITION_IDENTIFIER);
      string symbol=PositionGetString(POSITION_SYMBOL);
      int side=(int)PositionGetInteger(POSITION_TYPE);
      double lots=PositionGetDouble(POSITION_VOLUME), entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      rows+="TRADE\t"+TP_Int(id)+"\t"+symbol+"\t"+(side==0 ? "BUY" : "SELL")+"\t"+TP_Num(lots)+"\t"+TP_Num(sl)+"\t"+TP_Num(tp)+"\t"+
         TP_Num(TP_Risk(id,symbol,side,lots,entry,sl))+"\t"+TP_Source(PositionGetString(POSITION_COMMENT))+"\t"+TP_Int(PositionGetInteger(POSITION_TIME))+"\r\n";
      count++;
   }
#else
   for(int i=0;i<OrdersTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderType()>OP_SELL) continue;
      long id=OrderTicket();
      rows+="TRADE\t"+TP_Int(id)+"\t"+OrderSymbol()+"\t"+(OrderType()==OP_BUY ? "BUY" : "SELL")+"\t"+TP_Num(OrderLots())+"\t"+TP_Num(OrderStopLoss())+"\t"+TP_Num(OrderTakeProfit())+"\t"+
         TP_Num(TP_Risk(id,OrderSymbol(),OrderType(),OrderLots(),OrderOpenPrice(),OrderStopLoss()))+"\t"+TP_Source(OrderComment())+"\t"+TP_Int(OrderOpenTime())+"\r\n";
      count++;
   }
#endif
   return rows;
}

bool TP_PrepareOwnerSession()
{
   string session=tp_prefix+"SESSION_READY";
   if(!GlobalVariableCheck(session)) GlobalVariableTemp(session);
   if(GlobalVariableGet(session)==2) return true;
   if(!GlobalVariableSetOnCondition(session,1,0)) return false;
   // Temporary variables disappear when this terminal exits. Only the first
   // chart in the next session resets the persisted owner from the old process.
   GlobalVariableSet(tp_prefix+"OWNER",0);
   GlobalVariableSet(tp_prefix+"OWNER_HI",0);
   GlobalVariableSet(tp_prefix+"OWNER_LO",0);
   GlobalVariableSet(session,2);
   return true;
}

void TP_LocalInit()
{
   if(!TP_LocalBridge) return;
   if(StringLen(TP_AccountId)!=12 || StringLen(TP_BridgeToken)!=32)
      { Print("TradePilot: invalid desktop connection settings"); return; }
#ifdef __MQL5__
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      { Print("TradePilot local copying requires an MT5 hedging account"); return; }
#endif
   FolderCreate("TradePilotLocal",FILE_COMMON);
   tp_prefix="TPL_"+TP_Login()+"_"+TP_AccountId+"_";
   Print("TradePilot connection role: ",TP_IsSlave ? "Follower account" : "Lead account");
   // Every chart needs the saved broker offset before it can take over.
   tp_last_server=TimeCurrent();
   if(GlobalVariableCheck(tp_prefix+"OFFSET"))
   {
      tp_offset=(long)GlobalVariableGet(tp_prefix+"OFFSET");
      tp_clock_ready=true;
   }
   if(!TP_PrepareOwnerSession()) return;
   string lock=tp_prefix+"OWNER";
   if(!GlobalVariableCheck(lock)) GlobalVariableSet(lock,0);
   double previous=GlobalVariableGet(lock);
   long owner_chart=(long)GlobalVariableGet(tp_prefix+"OWNER_HI")*1000000000+(long)GlobalVariableGet(tp_prefix+"OWNER_LO");
   if(previous>0 && ((double)TimeLocal()-previous<15 || (owner_chart>0 && ChartSymbol(owner_chart)!="")))
      { Print("TradePilot: chart tools share the existing account connection"); return; }
   tp_owner=GlobalVariableSetOnCondition(lock,(double)TimeLocal(),previous);
   if(tp_owner)
   {
      GlobalVariableSet(tp_prefix+"OWNER_HI",(double)(ChartID()/1000000000));
      GlobalVariableSet(tp_prefix+"OWNER_LO",(double)(ChartID()%1000000000));
   }
}
void TP_LocalDeinit()
{
   TP_ChartDeinit();
   if(tp_prefix!="") GlobalVariableDel(tp_prefix+"PERMISSION_"+TP_Int(ChartID()));
   if(tp_owner) GlobalVariableSet(tp_prefix+"OWNER",0);
}
// Prefer a chart whose own advisor permission was explicitly enabled by the user.
// This never changes terminal/advisor permissions, and never treats a sent request as permission.
bool TP_OwnerPermissionCandidate()
{
   string mine=tp_prefix+"PERMISSION_"+TP_Int(ChartID());
   if(!GlobalVariableCheck(mine)) GlobalVariableTemp(mine);
   bool permitted=TP_TradingPermission();
   GlobalVariableSet(mine,permitted ? (double)TimeLocal() : 0);
   if(permitted) return true;
   long chart=ChartFirst();
   for(int i=0;i<100 && chart>=0;i++) {
      string key=tp_prefix+"PERMISSION_"+TP_Int(chart);
      if(chart!=ChartID() && GlobalVariableCheck(key)) {
         double stamp=GlobalVariableGet(key);
         if(stamp>0 && (double)TimeLocal()-stamp>=0 && (double)TimeLocal()-stamp<=5) return false;
      }
      chart=ChartNext(chart);
   }
   return true; // All permissions off: retain the connection, reporting permission false.
}
void TP_LocalPoll()
{
   if(!TP_LocalBridge || tp_prefix=="") return;
   if(!TP_PrepareOwnerSession()) return;
   if(!TP_OwnerPermissionCandidate()) {
      if(tp_owner) { tp_owner=false;GlobalVariableSet(tp_prefix+"OWNER",0); }
      return;
   }
   if(!tp_owner)
   {
      double previous=GlobalVariableGet(tp_prefix+"OWNER");
      long owner_chart=(long)GlobalVariableGet(tp_prefix+"OWNER_HI")*1000000000+(long)GlobalVariableGet(tp_prefix+"OWNER_LO");
      // A slow broker operation must not create a second bridge owner. Transfer
      // a stale lease only after its actual chart has disappeared.
      if(previous==0 || ((double)TimeLocal()-previous>15 && owner_chart>0 && ChartSymbol(owner_chart)==""))
      {
         tp_owner=GlobalVariableSetOnCondition(tp_prefix+"OWNER",(double)TimeLocal(),previous);
         if(tp_owner)
         {
            GlobalVariableSet(tp_prefix+"OWNER_HI",(double)(ChartID()/1000000000));
            GlobalVariableSet(tp_prefix+"OWNER_LO",(double)(ChartID()%1000000000));
         }
      }
      if(!tp_owner) return;
   }
   GlobalVariableSet(tp_prefix+"OWNER",(double)TimeLocal());
   TP_ConnectionPing();
   TP_Discovery();
   datetime now=TP_ServerNow();
   // A first connection during market closure must not infer a false timezone
   // from Friday's last quote. Wait for a fresh server tick, or use saved offset.
   if(!tp_clock_ready) return;
   tp_month=TP_Month(now);
   TP_Accounting(TP_MonthStart(now));
   tp_paid=false; tp_enabled=false; tp_lease=0;
   tp_reached=GlobalVariableCheck(tp_prefix+tp_month+"_HIT");
   string p[];
   if(TP_Read(".cfg",p) && ArraySize(p)==13 && p[11]=="6" && p[0]==TP_BridgeToken && (p[1]=="SLAVE")==TP_IsSlave)
   {
      tp_tier=StringToDouble(p[5]);
      // Persist the tier for independent monthly enforcement if the desktop app exits.
      if(MathIsValidNumber(tp_tier) && tp_tier>=1 && tp_tier<=100 && tp_tier==MathFloor(tp_tier))
         GlobalVariableSet(tp_prefix+"TIER",tp_tier);
      else tp_tier=0;
      if(tp_tier>0 && p[3]==tp_month)
      {
         double baseline=StringToDouble(p[6]), closed_start=StringToDouble(p[9]), floating_start=StringToDouble(p[10]);
         if(MathIsValidNumber(baseline) && baseline>0 && MathIsValidNumber(closed_start) && MathIsValidNumber(floating_start))
         {
            string key=tp_prefix+tp_month+"_CURRENT_BASE";
            if(!GlobalVariableCheck(key) || GlobalVariableGet(key)!=baseline ||
               !GlobalVariableCheck(key+"_C") || GlobalVariableGet(key+"_C")!=closed_start ||
               !GlobalVariableCheck(key+"_F") || GlobalVariableGet(key+"_F")!=floating_start)
            {
               GlobalVariableSet(key+"_C",closed_start);
               GlobalVariableSet(key+"_F",floating_start);
               GlobalVariableSet(key,baseline); // Commit marker last.
               GlobalVariablesFlush();
            }
            long revision=StringToInteger(p[12]);
            string reset_key=tp_prefix+tp_month+"_RESET_REVISION";
            long previous_revision=GlobalVariableCheck(reset_key) ? (long)GlobalVariableGet(reset_key) : 0;
            if(revision>previous_revision)
            {
               // A new Paid record resets this cycle, never erases trade history.
               GlobalVariableDel(tp_prefix+tp_month+"_HIT");
               GlobalVariableSet(reset_key,(double)revision); GlobalVariablesFlush();
               tp_reached=false;
            }
            tp_reset_revision=revision;
            tp_opening=baseline; tp_closed_start=closed_start; tp_float_start=floating_start;
         }
         tp_enabled=p[2]=="1"; tp_paid=p[4]=="1"; tp_lease=(datetime)StringToInteger(p[8]);
         if(p[7]=="1") tp_reached=true;
      }
   }
   else if(GlobalVariableCheck(tp_prefix+"TIER")) tp_tier=GlobalVariableGet(tp_prefix+"TIER");
   if(!MathIsValidNumber(tp_tier) || tp_tier<1 || tp_tier>100 || tp_tier!=MathFloor(tp_tier)) { tp_tier=0; tp_enabled=false; }
   if(TP_IsSlave)
   {
      if(TP_HistoryReady() && tp_opening>0 && tp_tier>0 && tp_closed-tp_closed_start+tp_float-tp_float_start>=tp_opening*tp_tier/100.0) tp_reached=true;
      // An unfinished closure from a prior month must complete before reopening.
      bool closing=GlobalVariableCheck(tp_prefix+"CLOSING");
      if(tp_reached || closing)
      {
         if(tp_reached) GlobalVariableSet(tp_prefix+tp_month+"_HIT",1);
         GlobalVariableSet(tp_prefix+"CLOSING",1); GlobalVariablesFlush();
         TP_CloseAll();
         if(TP_Positions()==0 && TP_Pending()==0) GlobalVariableDel(tp_prefix+"CLOSING");
         else tp_enabled=false;
      }
      if(TerminalInfoInteger(TERMINAL_CONNECTED)) TP_Command();
   }
   // Refresh account values after command execution/closure, before publishing.
   TP_Accounting(TP_MonthStart(now));
   int count=0; string trades=TP_Trades(count);
#ifdef __MQL5__
   string platform="MT5";
#else
   string platform="MT4";
#endif
   string meta="META\t"+TP_AccountId+"\t"+TP_Login()+"\t"+TP_Server()+"\t"+platform+"\t"+tp_month+"\t"+TimeToString(now,TIME_DATE|TIME_SECONDS)+"\t"+
      TP_Num(TP_Balance())+"\t"+TP_Num(tp_opening)+"\t"+TP_Num(tp_closed)+"\t"+TP_Num(tp_float)+"\t"+
      IntegerToString(TP_Positions())+"\t"+IntegerToString(TP_Pending())+"\t"+(TerminalInfoInteger(TERMINAL_CONNECTED) ? "1" : "0")+"\t"+
      (TP_HistoryReady() ? "1" : "0")+"\t"+(tp_reached ? "1" : "0")+"\t"+TerminalInfoString(TERMINAL_DATA_PATH)+"\t6\t"+TP_Int(TimeGMT())+"\t"+((TP_TradingPermission()) ? "1" : "0")+"\t"+TP_Int(tp_reset_revision)+"\r\n";
   TPDL_Publish();
   TP_PermissionDetails(platform);
   TP_PendingDetails(now);
   TP_Atomic(".state",meta+trades+"END\t"+IntegerToString(count)+"\r\n");
   TP_StatementHistory(now);
}
#endif
