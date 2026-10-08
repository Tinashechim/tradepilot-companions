// Read-only carry-over detail panel. Never sends or closes orders.
bool tpc_open=false;
int tpc_page=0;bool tpc_entries=false;int tpc_entry_page=0;
string tpc_signature="";
void TPC_Close()
{
 tpc_open=false;tpc_signature="";ObjectsDeleteAll(0,"TradePilot_CARRY_DETAIL_");ChartRedraw();
}
void TPC_Render()
{
 string help="Older baskets retain their original daily target. They close only when their own net target is reached and terminal trading is permitted. Today's target does not close them.";
 string clickable[]={"TITLE","BASKETS_LABEL","BASKETS_VALUE","POSITIONS_LABEL","POSITIONS_VALUE","PROFIT_LABEL","PROFIT_VALUE"};
 for(int j=0;j<ArraySize(clickable);j++) ObjectSetString(0,"TradePilot_CARRY_"+clickable[j],OBJPROP_TOOLTIP,help+" Click to view entry dates.");
 if(!tpc_open)return;
 datetime periods[],entry_periods[],entry_times[];string entry_texts[];int counts[];datetime first[];
 datetime current=GetSessionStartForTime(TPDL_Now());
#ifdef __MQL5__
 int total=PositionsTotal();string currency=AccountInfoString(ACCOUNT_CURRENCY);
#else
 int total=OrdersTotal();string currency=AccountCurrency();
#endif
 for(int i=0;i<total;i++) {
#ifdef __MQL5__
  ulong ticket=PositionGetTicket(i);if(ticket==0)continue;datetime opened=(datetime)PositionGetInteger(POSITION_TIME);string symbol=PositionGetString(POSITION_SYMBOL);
#else
  if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)||(OrderType()!=OP_BUY&&OrderType()!=OP_SELL))continue;datetime opened=OrderOpenTime();ulong ticket=(ulong)OrderTicket();string symbol=OrderSymbol();
#endif
  datetime period=GetSessionStartForTime(opened);if(period<=0||period>=current)continue;
  int e=ArraySize(entry_texts);ArrayResize(entry_texts,e+1);ArrayResize(entry_periods,e+1);ArrayResize(entry_times,e+1);entry_periods[e]=period;entry_times[e]=opened;entry_texts[e]=TimeToString(opened,TIME_DATE|TIME_MINUTES)+" | "+symbol+" | #"+(string)ticket;
  int n=-1;for(int j=0;j<ArraySize(periods);j++)if(periods[j]==period){n=j;break;}
  if(n<0){n=ArraySize(periods);ArrayResize(periods,n+1);ArrayResize(counts,n+1);ArrayResize(first,n+1);periods[n]=period;counts[n]=0;first[n]=opened;}
  counts[n]++;if(opened<first[n])first[n]=opened;
 }
 for(int i=1;i<ArraySize(periods);i++)for(int j=i;j>0&&periods[j]<periods[j-1];j--){datetime d=periods[j];periods[j]=periods[j-1];periods[j-1]=d;d=first[j];first[j]=first[j-1];first[j-1]=d;int c=counts[j];counts[j]=counts[j-1];counts[j-1]=c;}
 for(int i=1;i<ArraySize(entry_times);i++)for(int j=i;j>0&&entry_times[j]<entry_times[j-1];j--){datetime d=entry_times[j];entry_times[j]=entry_times[j-1];entry_times[j-1]=d;d=entry_periods[j];entry_periods[j]=entry_periods[j-1];entry_periods[j-1]=d;string row=entry_texts[j];entry_texts[j]=entry_texts[j-1];entry_texts[j-1]=row;}
 int pages=MathMax(1,ArraySize(periods));tpc_page=MathMax(0,MathMin(tpc_page,pages-1));
 string lines[];ArrayResize(lines,10);for(int k=0;k<10;k++)lines[k]="";
 if(ArraySize(periods)>0){
  datetime period=periods[tpc_page];double actual=0,adjusted=0,costs=0,spread=0,commission=0,swap=0,broker_fees=0;bool fresh=false,exits=false;
  bool verified=TP_BasketResults(period,actual,adjusted);bool fees=TP_BasketChargeDetails(period,costs,spread,fresh,exits,commission,swap,broker_fees);
  double target=GetSessionTargetMoney(period),remaining=MathMax(0,target-adjusted);
  lines[0]="Basket "+TimeToString(period,TIME_DATE)+" | Open positions: "+(string)counts[tpc_page];
  lines[1]="First entry: "+TimeToString(first[tpc_page],TIME_DATE|TIME_MINUTES);
  lines[2]="Net target: "+currency+" "+DoubleToString(target,2);
  lines[3]="Net profit/loss: "+(verified?currency+" "+DoubleToString(actual,2):"Verification pending");
  lines[4]="Remaining: "+(verified?currency+" "+DoubleToString(remaining,2):"Verification pending")+" | Progress: "+(verified&&target>0?DoubleToString(MathMax(0,MathMin(100,adjusted/target*100)),1)+"%":"Verification pending");
  lines[5]="Commission = "+(fees?currency+" "+DoubleToString(commission,2):"Verification pending");
  lines[6]="Swap = "+(fees?currency+" "+DoubleToString(swap,2):"Verification pending");
  lines[7]="Broker fees = "+(fees?currency+" "+DoubleToString(broker_fees,2):"Verification pending");
  lines[8]="Spread = "+(fees&&fresh?currency+" "+DoubleToString(spread,2)+" (current estimate)":"Quote pending");
  lines[9]="Status: "+(!verified?"Verification pending":remaining>0?"Working toward target":"Target reached; trading permission required to close");
 }else {
  lines[0]="No older open baskets.";
  lines[1]=tpc_entries?"No older open trade entries to display.":"Today's positions stay in Current Basket.";
 }
 int display_page=tpc_page,display_pages=pages;
 if(tpc_entries&&ArraySize(periods)>0){
  string selected[];for(int i=0;i<ArraySize(entry_texts);i++)if(entry_periods[i]==periods[tpc_page]){int n=ArraySize(selected);ArrayResize(selected,n+1);selected[n]=entry_texts[i];}
  display_pages=MathMax(1,(ArraySize(selected)+5)/6);tpc_entry_page=MathMax(0,MathMin(tpc_entry_page,display_pages-1));display_page=tpc_entry_page;
  for(int i=0;i<ArraySize(lines);i++)lines[i]="";
  lines[0]="Basket "+TimeToString(periods[tpc_page],TIME_DATE)+" | Open positions: "+(string)counts[tpc_page];lines[1]="Trade entry date/time | Symbol | Broker ticket";
  for(int i=0;i<6;i++){int n=tpc_entry_page*6+i;if(n<ArraySize(selected))lines[i+2]=selected[n];}
 }
 string signature=(tpc_entries?"Entries":"Progress")+"|"+(string)display_page+"|"+(string)tpc_page+"|"+(string)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)+"|"+(string)PanelY()+"|"+(string)S(560);for(int i=0;i<ArraySize(lines);i++)signature+="|"+lines[i];
 tpc_signature=signature; // Repaint last so refreshed tool labels cannot cover this view.
 // Keep navigation buttons alive while broker results refresh.
 int w=S(560),h=S(372),x=MathMax(S(8),(int)(ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-w)/2),y=PanelY()+S(28);
 CreateRectangle("TradePilot_CARRY_DETAIL_BG",x,y,w,h,C'25,30,40',C'85,95,110');
 CreateLabel("TradePilot_CARRY_DETAIL_TITLE",tpc_entries?"CARRY-OVER TRADE ENTRIES":"CARRY-OVER BASKET PROGRESS",x+S(12),y+S(10),FontSize(BASE_FONT_SECTION),clrWhite);
 CreateLabel("TradePilot_CARRY_DETAIL_EXPLAIN1","Each basket retains its original broker-day target.",x+S(12),y+S(36),FontSize(BASE_FONT_SMALL),clrWhite);
 CreateLabel("TradePilot_CARRY_DETAIL_EXPLAIN2","Closes at its own net target when trading is allowed.",x+S(12),y+S(53),FontSize(BASE_FONT_SMALL),clrWhite);
 for(int i=0;i<ArraySize(lines);i++){string name="TradePilot_CARRY_DETAIL_ROW"+(string)i;CreateLabel(name,StringLen(lines[i])>68?StringSubstr(lines[i],0,65)+"...":lines[i],x+S(12),y+S(79+i*24),FontSize(BASE_FONT_SMALL),clrWhite);ObjectSetString(0,name,OBJPROP_TOOLTIP,lines[i]+". Net results include broker charges once; progress follows this basket's saved Apply wins/losses choices.");}
 CreateButton("TradePilot_CARRY_DETAIL_PREV","Back",x+S(12),y+S(338),S(74),S(22),display_page>0?C'35,115,80':C'140,45,45');
 CreateLabel("TradePilot_CARRY_DETAIL_PAGE",(string)(display_page+1)+" / "+(string)display_pages,x+S(105),y+S(342),FontSize(BASE_FONT_SMALL),clrWhite);
 CreateButton("TradePilot_CARRY_DETAIL_NEXT","Next",x+S(180),y+S(338),S(74),S(22),display_page+1<display_pages?C'35,115,80':C'140,45,45');
 CreateButton("TradePilot_CARRY_DETAIL_VIEW",tpc_entries?"Progress":"Trades",x+S(270),y+S(338),S(90),S(22),C'55,60,70');
 ObjectSetString(0,"TradePilot_CARRY_DETAIL_VIEW",OBJPROP_TOOLTIP,tpc_entries?"Return to this basket’s progress summary.":"View each open trade’s entry date, symbol and broker ticket for this basket.");
 CreateButton("TradePilot_CARRY_DETAIL_CLOSE","Close",x+w-S(86),y+S(338),S(74),S(22),C'140,45,45');
 ObjectSetString(0,"TradePilot_CARRY_DETAIL_PREV",OBJPROP_TOOLTIP,"View the previous basket or trade-entry page.");ObjectSetString(0,"TradePilot_CARRY_DETAIL_NEXT",OBJPROP_TOOLTIP,"View the next basket or trade-entry page.");ObjectSetString(0,"TradePilot_CARRY_DETAIL_CLOSE",OBJPROP_TOOLTIP,"Close this read-only list. No trades are closed.");
 string controls[]={"PREV","NEXT","VIEW","CLOSE"};for(int i=0;i<ArraySize(controls);i++)ObjectSetInteger(0,"TradePilot_CARRY_DETAIL_"+controls[i],OBJPROP_ZORDER,100);
 ChartRedraw();
}
bool TPC_Event(string name)
{
 if(StringFind(name,"TradePilot_CARRY_")!=0)return false;
 if(ObjectFind(0,name)>=0)ObjectSetInteger(0,name,OBJPROP_STATE,false);
 if(name=="TradePilot_CARRY_DETAIL_CLOSE") {TPC_Close();return true;}
 if(name=="TradePilot_CARRY_DETAIL_VIEW"){tpc_entries=!tpc_entries;tpc_entry_page=0;}
 else if(name=="TradePilot_CARRY_DETAIL_NEXT"){if(tpc_entries)tpc_entry_page++;else tpc_page++;}
 else if(name=="TradePilot_CARRY_DETAIL_PREV"){if(tpc_entries)tpc_entry_page--;else tpc_page--;}
 else if(StringFind(name,"TradePilot_CARRY_DETAIL_")==0)return true;
 else {tpc_open=!tpc_open;tpc_page=0;tpc_entries=false;tpc_entry_page=0;if(!tpc_open){TPC_Close();return true;}}
 TPC_Render();return true;
}
