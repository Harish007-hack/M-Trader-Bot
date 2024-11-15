#include <Trade\Trade.mqh>

input double risk_percentage = 1.0;                // Risk percentage
input double reward_ratio = 2.0;                   // Reward ratio
input ENUM_TIMEFRAMES timeframe_1m = PERIOD_M1;    // 1-minute timeframe (entry)
input ENUM_TIMEFRAMES timeframe_5m = PERIOD_M5;    // 5-minute timeframe (refined entry/exit)
input ENUM_TIMEFRAMES timeframe_15m = PERIOD_M15;  // 15-minute timeframe
input ENUM_TIMEFRAMES trend_timeframe_1h = PERIOD_H1;  // 1-hour timeframe
input ENUM_TIMEFRAMES trend_timeframe_4h = PERIOD_H4;  // 4-hour timeframe
input double profit_threshold = 10.0;  // Profit Threshold

double initial_balance;
double lot_size = 0.2; 
double max_lot_size = 1.0;  // Limit the max lot size            
double global_stop_loss;
double global_take_profit;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_time = TimeCurrent();
   Print("Tick received. Current time: ", TimeToString(current_time));

   // Check if there are open positions and close them if profit exceeds $50
   CloseTradeIfProfitIsEnough(profit_threshold);

   // Check if there are no open positions, then attempt to open a new trade
   if (PositionsTotal() == 0) 
   {
      // Check for sideways market zones
      if (IsSidewaysMarket()) 
      {
         Print("Market is sideways.");
         return;
      }

      // Identify trendlines and liquidity points
      if (IsTrendlineValid())
      {
         double entry_price = NormalizeDouble(GetLiquidityPoint(),2);
         if (entry_price > 0)
         {
            global_stop_loss = NormalizeDouble(CalculateStopLoss(entry_price),1);
            global_take_profit = NormalizeDouble(CalculateTakeProfit(entry_price, global_stop_loss),1);
            Print("Attempting to open trade at entry price: ", entry_price);

            OpenTrade(entry_price, global_stop_loss, global_take_profit);
         }
         else
         {
            Print("Invalid entry price.");
         }
      }
      else
      {
         Print("Trendline not valid.");
      }
   }
}

//+------------------------------------------------------------------+
//| Custom functions                                                 |
//+------------------------------------------------------------------+
bool IsSidewaysMarket()
{
   double range = iHigh(_Symbol, timeframe_15m, 0) - iLow(_Symbol, timeframe_15m, 0);
   return (range < 10 * _Point);  // Adjust threshold as needed
}

bool IsTrendlineValid()
{
   // Retrieve the moving averages for both 1-hour and 4-hour timeframes
   double ma_short_1h = iMA(_Symbol, trend_timeframe_1h, 20, 0, MODE_SMA, PRICE_CLOSE);
   double ma_long_1h = iMA(_Symbol, trend_timeframe_1h, 50, 0, MODE_SMA, PRICE_CLOSE);
   double ma_short_4h = iMA(_Symbol, trend_timeframe_4h, 20, 0, MODE_SMA, PRICE_CLOSE);
   double ma_long_4h = iMA(_Symbol, trend_timeframe_4h, 50, 0, MODE_SMA, PRICE_CLOSE);

   // Check if we have an uptrend or downtrend on both timeframes
   bool uptrend = (ma_short_1h > ma_long_1h) && (ma_short_4h > ma_long_4h);
   bool downtrend = (ma_short_1h < ma_long_1h) && (ma_short_4h < ma_long_4h);

   // Return true for uptrend or downtrend; otherwise, false
   return uptrend || downtrend;
}

double GetLiquidityPoint()
{
   double pivot = (iHigh(_Symbol, timeframe_5m, 1) + iLow(_Symbol, timeframe_5m, 1) + iClose(_Symbol, timeframe_5m, 1)) / 3;
   return pivot;
}

double GetMinStopDistance()
{
   long stop_level = 0.0;

   // Retrieve the minimum stop level for the symbol in points
   if (!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stop_level))
   {
      Print("Error: Failed to retrieve minimum stop level.");
      return 10 * _Point;  // Default to 10 points if retrieval fails
   }

   return stop_level * _Point;
}

double CalculateStopLoss(double entry_price)
{
   int atr_handle = iATR(_Symbol, timeframe_5m, 14);  // ATR period of 14 on 5-minute timeframe

   if (atr_handle == INVALID_HANDLE)
   {
      Print("Failed to create ATR indicator handle");
      return 0;
   }

   double atr_values[];
   int copied = CopyBuffer(atr_handle, 0, 0, 1, atr_values);  // Get the most recent ATR value (shift 0)
   if (copied <= 0)
   {
      Print("Failed to get ATR value");
      return 0;
   }

   double atr = atr_values[0];
   double min_stop_distance = GetMinStopDistance();  // Ensure stop loss meets minimum distance

   double stop_loss = NormalizeDouble(entry_price - (atr * 1.5), _Digits);
   if (MathAbs(entry_price - stop_loss) < min_stop_distance)
   {
      stop_loss = entry_price - min_stop_distance;  // Adjust to meet minimum stop distance
   }
   return stop_loss;
}

double CalculateTakeProfit(double entry_price, double stop_loss_value)
{
   double risk_pips = MathAbs(entry_price - stop_loss_value);
   double take_profit = NormalizeDouble(entry_price + (risk_pips * reward_ratio), _Digits);
   
   // Adjust take profit if it's too close
   double min_stop_distance = GetMinStopDistance();
   if (MathAbs(entry_price - take_profit) < min_stop_distance)
   {
      take_profit = entry_price + min_stop_distance;
   }

   return take_profit;
}

void OpenTrade(double entry_price, double stop_loss_value, double take_profit_value)
{
   double min_stop_distance = GetMinStopDistance();

   // Validate stop loss and take profit values
   if (MathAbs(entry_price - stop_loss_value) < min_stop_distance)
   {
      Print("Stop loss adjusted to meet minimum stop distance.");
      stop_loss_value = entry_price - min_stop_distance;
   }

   if (MathAbs(entry_price - take_profit_value) < min_stop_distance)
   {
      Print("Take profit adjusted to meet minimum stop distance.");
      take_profit_value = entry_price + min_stop_distance;
   }

   // Risk-based lot size calculation
   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * (risk_percentage / 100.0);
   double stop_loss_distance = MathAbs(entry_price - stop_loss_value);
   double calculated_lot_size = risk_amount / stop_loss_distance;
   //Print(calculated_lot_size);

   // Ensure the lot size is within acceptable limits
   // the mathmax param is min lot size i.e 0.01
   lot_size = NormalizeDouble(MathMin(calculated_lot_size, max_lot_size), 2);
   //Print(lot_size);

   // Attempt to open the trade
   if (trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lot_size, entry_price, stop_loss_value, take_profit_value, "Trendline Strategy"))
   {
      Print("Trade opened successfully with adjusted stops.");
   }
   else if (trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lot_size, entry_price, stop_loss_value, take_profit_value, "Trendline Strategy"))
   {
      Print("Trade opened successfully with adjusted stops.");
   }
   else
   {
      Print("Error: Trade failed to open with adjusted stops.");
   }
}

//+------------------------------------------------------------------+
//| Close trade if profit exceeds $50                                |
//+------------------------------------------------------------------+
void CloseTradeIfProfitIsEnough(double target_profit)
{
   // Loop through open positions
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         double current_profit = PositionGetDouble(POSITION_PROFIT);

         // If profit is greater than or equal to the target, close the position
         if (current_profit >= target_profit)
         {
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               if (trade.PositionClose(ticket))
               {
                  //Print("Buy position closed with profit of: ", current_profit);
               }
               else
               {
                  //Print("Error closing buy position: ", GetLastError());
               }
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               if (trade.PositionClose(ticket))
               {
                  //Print("Sell position closed with profit of: ", current_profit);
               }
               else
               {
                  //Print("Error closing sell position: ", GetLastError());
               }
            }
         }
      }
   }
}
