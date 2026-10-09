#ifndef TRADEPILOT_PANEL_VISIBILITY
#define TRADEPILOT_PANEL_VISIBILITY
bool TP_IsBasketObject(string key)
{
 if(StringFind(key,"TradePilot_")!=0)return false;
 string suffix=StringSubstr(key,StringLen("TradePilot_"));
 string names="|CURRENT_BORDER|BASKET_TITLE|POSITIONS_LABEL|POSITIONS_VALUE|PROFIT_LABEL|PROFIT_VALUE|TP_VALUE_LABEL|TARGET_VALUE|TARGET_UNIT|STATUS_LABEL|STATUS_VALUE|";
 return StringFind(names,"|"+suffix+"|")>=0 || StringFind(suffix,"CARRY_")==0 || StringFind(suffix,"BASKET_")==0 || StringFind(suffix,"FLOAT_")==0 || suffix=="FLOATING_EQUIVALENTS" || StringFind(suffix,"TOTAL_")==0;
}
void TP_ApplyBasketVisibility(string name)
{
 // Apply before any intermediate chart redraw can expose an OFF basket.
 if(TP_IsBasketObject(name))ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,tp_basket_open?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
}
void TP_PanelVisibility()
{
 int main_x=PanelX(),basket_x=PanelX()+PanelWidth()+S(12),top=PanelY();
 for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--) {
  string key=ObjectName(0,i,-1,-1);
  if(StringFind(key,"TradePilot_")!=0 || StringFind(key,"CONFIRM")>=0)continue;
  long type=ObjectGetInteger(0,key,OBJPROP_TYPE);
  if(type==OBJ_HLINE||type==OBJ_VLINE||type==OBJ_TREND)continue;
  if(key=="TPUI_MAIN_TOGGLE"||key=="TPUI_BASKET_TOGGLE"||key=="TPUI_MAIN_COLLAPSED"||key=="TPUI_MAIN_CAPTION"||key=="TPUI_BASKET_COLLAPSED"||key=="TPUI_BASKET_CAPTION")continue;
  if(key=="TradePilot_TARGET_UNIT"||key=="TradePilot_CARRY_CURRENCY"||key=="TradePilot_REMAINING_UNIT") {ObjectSetInteger(0,key,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);continue;}
  long x=ObjectGetInteger(0,key,OBJPROP_XDISTANCE);
  // Basket ownership is fixed by object identity, not transient coordinates
  // while a resize/update rebuilds labels at their original main-column positions.
  bool basket=TP_IsBasketObject(key);
  bool open=basket?tp_basket_open:tp_main_open;
  long desired=open?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;
  if(ObjectGetInteger(0,key,OBJPROP_TIMEFRAMES)!=desired)ObjectSetInteger(0,key,OBJPROP_TIMEFRAMES,desired);
 }
 // Keep zoom below the switch row, clear of its 24-pixel hit area.
 string zoom[]={"TradePilot_SCALE_MINUS","TradePilot_SCALE_VALUE","TradePilot_SCALE_PLUS"};
 // Render last so the main section background cannot cover the zoom row.
 int zoom_y=top+S(43),zoom_left=ValueX();
 CreateButton("TradePilot_SCALE_MINUS","-",zoom_left,zoom_y,S(18),S(20),C'55,60,70');
 if(ObjectFind(0,"TradePilot_SCALE_VALUE")<0)CreateEdit("TradePilot_SCALE_VALUE",DoubleToString(manual_panel_scale*100.0,1)+"%",zoom_left+S(21),zoom_y,S(46),S(20));
 CreateButton("TradePilot_SCALE_PLUS","+",zoom_left+S(70),zoom_y,S(18),S(20),C'55,60,70');
 int zoom_x[]={0,21,70};
 for(int i=0;i<ArraySize(zoom);i++) {
  ObjectSetInteger(0,zoom[i],OBJPROP_YDISTANCE,top+S(43));
  ObjectSetInteger(0,zoom[i],OBJPROP_XDISTANCE,zoom_left+S(zoom_x[i]));
  ObjectSetInteger(0,zoom[i],OBJPROP_YSIZE,S(20));
  ObjectSetInteger(0,zoom[i],OBJPROP_TIMEFRAMES,tp_main_open?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
 }
 ObjectSetInteger(0,"TradePilot_SCALE_VALUE",OBJPROP_ALIGN,ALIGN_CENTER);
 ObjectSetString(0,"TradePilot_SCALE_VALUE",OBJPROP_TOOLTIP,"Type a zoom percentage from 50% to 150%, then press Enter. Minus and plus change zoom by one percentage point.");
 ObjectSetString(0,"TradePilot_SCALE_MINUS",OBJPROP_TOOLTIP,"Make all TradePilot panels one percentage point smaller.");
 ObjectSetString(0,"TradePilot_SCALE_PLUS",OBJPROP_TOOLTIP,"Make all TradePilot panels one percentage point larger.");
 ObjectSetInteger(0,"TradePilot_DAILY_MODE_BUTTON",OBJPROP_YDISTANCE,top+S(67));
 ObjectSetInteger(0,"TradePilot_DAILY_MODE_BUTTON",OBJPROP_XDISTANCE,ValueX());
 ObjectSetInteger(0,"TradePilot_DAILY_TITLE",OBJPROP_FONTSIZE,TP_HeaderFont("DAILY PERFORMANCE",FontSize(BASE_FONT_SECTION),ValueX()-LabelX()-S(8),S(18)));
 // Identical compact headers and red/green switches; hiding panels does not change trading permissions.
 CreateRectangle("TPUI_MAIN_COLLAPSED",main_x,top,S(304),S(31),C'24,29,39',clrSlateGray);
 CreateLabel("TPUI_MAIN_CAPTION","TRADEPILOT",main_x+S(12),top+S(8),FontSize(BASE_FONT_SECTION),C'90,180,255');
 CreateRectangle("TPUI_BASKET_COLLAPSED",basket_x,top,S(304),S(31),C'24,29,39',clrSlateGray);
 CreateLabel("TPUI_BASKET_CAPTION","CURRENT BASKET",basket_x+S(12),top+S(8),FontSize(BASE_FONT_SECTION),C'90,180,255');
 ObjectSetInteger(0,"TPUI_MAIN_COLLAPSED",OBJPROP_TIMEFRAMES,tp_main_open?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
 ObjectSetInteger(0,"TPUI_MAIN_CAPTION",OBJPROP_TIMEFRAMES,tp_main_open?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
 ObjectSetInteger(0,"TPUI_BASKET_COLLAPSED",OBJPROP_TIMEFRAMES,tp_basket_open?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
 ObjectSetInteger(0,"TPUI_BASKET_CAPTION",OBJPROP_TIMEFRAMES,tp_basket_open?OBJ_NO_PERIODS:OBJ_ALL_PERIODS);
 CreateButton("TPUI_MAIN_TOGGLE",tp_main_open?"ON":"OFF",main_x+S(244),top+S(6),S(50),S(24),tp_main_open?C'35,115,80':C'140,45,45');
 CreateButton("TPUI_BASKET_TOGGLE",tp_basket_open?"ON":"OFF",basket_x+S(244),top+S(6),S(50),S(24),tp_basket_open?C'35,115,80':C'140,45,45');
 string switches[]={"TPUI_MAIN_TOGGLE","TPUI_BASKET_TOGGLE"};
 for(int i=0;i<ArraySize(switches);i++) {ObjectSetInteger(0,switches[i],OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);ObjectSetInteger(0,switches[i],OBJPROP_BACK,false);ObjectSetInteger(0,switches[i],OBJPROP_ZORDER,100);}
 // Collapsed panels retain only their compact headers, never an opaque full-height block.
 ObjectSetInteger(0,"TradePilot_PANEL",OBJPROP_YSIZE,tp_main_open?PanelHeight()-S(20):0);
 ObjectSetInteger(0,"TradePilot_HEADER",OBJPROP_YSIZE,tp_main_open?S(42):0);
 ObjectSetInteger(0,"TradePilot_BASKET_COLUMN_BG",OBJPROP_YSIZE,tp_basket_open?S(458):0);
 ObjectSetInteger(0,"TradePilot_CURRENT_BORDER",OBJPROP_YSIZE,tp_basket_open?S(346):0);
 ObjectSetInteger(0,"TradePilot_CARRY_BORDER",OBJPROP_YSIZE,tp_basket_open?S(108):0);
 ObjectSetString(0,"TPUI_MAIN_TOGGLE",OBJPROP_TOOLTIP,"Show or hide Daily Performance, Daily Loss Limit and Position Sizer. Starts OFF. This only changes what you see; it does not stop connection or trade management.");
 ObjectSetString(0,"TPUI_BASKET_TOGGLE",OBJPROP_TOOLTIP,"Show or hide Current Basket and Carry-over progress. Starts OFF. Existing basket management continues while hidden.");
}
bool TP_PanelToggle(string name)
{
 if(name=="TPUI_MAIN_TOGGLE")tp_main_open=!tp_main_open;
 else if(name=="TPUI_BASKET_TOGGLE")tp_basket_open=!tp_basket_open;
 else return false;
 ObjectSetInteger(0,name,OBJPROP_STATE,false);
 bool basket_toggle=(name=="TPUI_BASKET_TOGGLE");
 string headers[3];
 headers[0]=basket_toggle?"TPUI_BASKET_COLLAPSED":"TPUI_MAIN_COLLAPSED";
 headers[1]=basket_toggle?"TPUI_BASKET_CAPTION":"TPUI_MAIN_CAPTION";
 headers[2]=name;
 for(int i=0;i<ArraySize(headers);i++)ObjectDelete(0,headers[i]);
 // Recreate screen objects in background-before-controls order. A timeframe
 // mask alone can leave previously hidden controls blank after expansion.
 // Preserve every input, including an unconfirmed daily loss-limit draft.
 string edits[],values[];
 int count=0;
 for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--) {
  string key=ObjectName(0,i,-1,-1);
  if(StringFind(key,"TradePilot_")!=0 || StringFind(key,"CONFIRM")>=0)continue;
  long type=ObjectGetInteger(0,key,OBJPROP_TYPE);
  if(type==OBJ_HLINE||type==OBJ_VLINE||type==OBJ_TREND)continue;
  if(TP_IsBasketObject(key)!=basket_toggle)continue;
  if(type==OBJ_EDIT) {
   ArrayResize(edits,count+1);ArrayResize(values,count+1);
   edits[count]=key;values[count]=ObjectGetString(0,key,OBJPROP_TEXT);count++;
  }
  ObjectDelete(0,key);
 }
 RebuildResponsivePanel();
 for(int i=0;i<count;i++)if(ObjectFind(0,edits[i])>=0)ObjectSetString(0,edits[i],OBJPROP_TEXT,values[i]);
 UpdatePanel();ChartRedraw();return true;
}
#endif

