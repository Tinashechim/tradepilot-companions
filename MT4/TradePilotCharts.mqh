// One shared bridge owner; each chart retains its own interactive tools/layout.
#ifndef TRADEPILOT_CHART_BINDING
#define TRADEPILOT_CHART_BINDING
long tp_bind_chart=0;
string tp_bind_nonce="",tp_bind_symbol="";
int tp_bind_period=0;
datetime tp_bind_started=0;

string TP_ChartKey(long chart) { return tp_prefix+"CHART_"+TP_Int(chart); }
string TP_BindStem() { return "TradePilot-bind-"+TP_AccountId+"-"+TP_Int(tp_bind_chart)+"-"+tp_bind_nonce; }


void TP_ChartPoll()
{
   if(!TP_LocalBridge || tp_prefix=="") return;
   datetime now=TimeLocal();
   GlobalVariableSet(TP_ChartKey(ChartID()),(double)now);
   if(!tp_owner) return;
   if(tp_bind_chart>0)
   {
      if(ChartSymbol(tp_bind_chart)!=tp_bind_symbol || (int)ChartPeriod(tp_bind_chart)!=tp_bind_period)
         { tp_bind_chart=0; return; }
      string reply[];
      if(TP_Read(".bindready",reply) && ArraySize(reply)==5 && reply[0]=="BIND_READY" &&
         reply[1]==TP_BridgeToken && reply[2]==tp_bind_nonce && reply[3]==TP_Int(tp_bind_chart))
      {
         if(reply[4]=="OK")
         {
            string path="\\Files\\TradePilotBind\\"+TP_BindStem()+".tpl";
            if(!ChartApplyTemplate(tp_bind_chart,path)) Print("TradePilot: could not attach chart tools. Error ",GetLastError());
         }
         else if(reply[4]=="BUSY") Print("TradePilot: ",tp_bind_symbol," chart already has another advisor; its tools were preserved.");
         tp_bind_chart=0;
         return;
      }
      if(now-tp_bind_started>15) tp_bind_chart=0;
      return;
   }
   long chart=ChartFirst();
   for(int i=0;i<1000 && chart>=0;i++)
   {
      if(chart!=ChartID() && ChartSymbol(chart)!="")
      {
         string key=TP_ChartKey(chart),attempt=key+"_TRY";
         bool attached=GlobalVariableCheck(key) && now-(datetime)GlobalVariableGet(key)<10;
         bool cooling=GlobalVariableCheck(attempt) && now-(datetime)GlobalVariableGet(attempt)<30;
         if(!attached && !cooling)
         {
            GlobalVariableSet(attempt,(double)now);
            tp_bind_chart=chart; tp_bind_symbol=ChartSymbol(chart); tp_bind_period=(int)ChartPeriod(chart);
            tp_bind_nonce=TP_Int(now)+"-"+TP_Int(GetTickCount()); tp_bind_started=now;
            string stem=TP_BindStem();
            if(!ChartSaveTemplate(chart,stem) || !ChartSaveTemplate(ChartID(),stem+"-owner"))
               { tp_bind_chart=0; return; }
#ifdef __MQL5__
            string platform="MT5";
#else
            string platform="MT4";
#endif
            TP_Atomic(".bind","BIND\t"+TP_BridgeToken+"\t"+TP_Login()+"\t"+TP_Server()+"\t"+platform+"\t"+
               TerminalInfoString(TERMINAL_DATA_PATH)+"\t"+TP_Int(TimeGMT())+"\t"+TP_Int(chart)+"\t"+
               tp_bind_nonce+"\t"+tp_bind_symbol+"\t"+IntegerToString(tp_bind_period)+"\r\n");
            return;
         }
      }
      chart=ChartNext(chart);
   }
}

void TP_ChartDeinit()
{
   if(tp_prefix!="") GlobalVariableDel(TP_ChartKey(ChartID()));
}
#endif
