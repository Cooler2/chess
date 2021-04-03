// Здесь реализация алгоритма принятия решений
unit AI;
interface
 var
  useLibrary:boolean=false; // разрешение использовать библиотеку дебютов
  turnTimeLimit:integer = 5; // turn time limit in seconds
  aiLevel:integer; // уровень сложности (1..4) - определяет момент, когда AI принимает решение о готовности хода
  aiSelfLearn:boolean=true; // режим самообучения: пополняет базу оценок позиций в ходе игры
  aiUseDB:boolean=true; // можно ли использовать БД оценок позиций

  aiStatus:string; // строка состояния работы AI
  moveReady:integer; // готовность хода - индекс выбранной доски продолжения (<=0 - ход не готов). Когда выставляется - AI ставится на паузу

 // Все эти процедуры вызываются только из главного потока
 procedure StartAI;
 procedure PauseAI;
 procedure ResumeAI;
 procedure StopAI;
 procedure AiTimer; // необходимо вызывать регулярно не менее 20 раз в секунду. Переключает режим работы AI
 procedure PlayerMadeTurn; // сообщает AI о том, что игрок сделал ход (вызывается в приостановленном состоянии)
 procedure AiPerfTest; // запустить тест производительности функций

 function IsAiStarted:boolean;
 function IsAiRunning:boolean;

 // Функция оценки позиции. Вычисленная оценка сохраняется в самой позиции, там же обновляются флаги.
 // Вместо вычисления, оценка может быть взята из базы оценок (вычисленных в других играх и сохранённых),
 // либо из кэша оценок (если такая позиция уже встречалась в текущей сессии, отключаемо).
 procedure EstimatePosition(boardIdx:integer;simplifiedMode:boolean;noCache:boolean=false);


implementation
 uses Apus.MyServis,Windows,SysUtils,Classes,gamedata,logic;

 const
  // штраф за незащищенную фигуру под боем
  bweight:array[0..6] of single=(0,1, 5.2, 3.1, 3.1, 9.3, 1000);
  bweight2:array[0..6] of single=(0,1, 3.1, 3.1, 5.2, 9.3, 1000);

 type
  TBasket=record
   first,last:integer;
  end;
  TBaskets=record
   links:array of integer;
   baskets:array[0..127] of TBasket; // weight должен быть в этих пределах
   lock:NativeInt;
   lastBasket:integer;
   count:integer;
   procedure Init;
   procedure Clear;
   procedure Add(b:integer); overload;
   procedure Add(boards:PInteger;count:integer); overload;
   function Get:integer;
  private
   procedure InternalAdd(idx:integer); inline;
  end;

  TThinkThread=class(TThread)
   id:integer;
   threadRunning,idle:boolean;
   counter,waitCounter:integer;
   procedure Execute; override;
{   procedure Reset;
   function ThinkIteration(root:integer;iteration:byte):boolean;
   procedure DoThink;}
  end;

  TAiState=(
   aiNoWork,  // AI стартовал, работы нет
   aiWorking, // задача поставлена, потоки могут работать (если не приостановлены)
   aiStopped  // работа остановилась - необходимо вмешательство
   );

 var
  started,running:boolean;
  //state:TAiState; // состояние выставляется из главного потока (из таймера)
  // рабочие потоки
  threads:array of TThinkThread;
  // список активных листьев
  active:TBaskets;

  // Для статистики
  startTime:int64;
  secondsElapsed:integer;
  startEstCounter:integer;
  lastEstCounter:integer;
  lastStatTime:int64;

  // глобальные счётчики производительности
  estCounter:NativeInt;

 function IsMyTurn:boolean; // true - значит сейчас ход AI, false - игрока
  begin
   result:=curBoard.whiteTurn xor playerWhite;
  end;

 // оценка позиции (rate - за черных)
 procedure EstimatePosition(boardIdx:integer;simplifiedMode:boolean;noCache:boolean=false);
  const
   PawnRate:array[0..7] of single=(1, 1, 1, 1.02, 1.1, 1.3, 1.9, 2);
  var
   i,j,n,m,x,y,f:integer;
   v:single;
   maxblack,maxwhite:single;
   hash:int64;
   h:integer;
   beatable:TBeatable;
   b:PBoard;
   cachedRate:single;
   cachedFromDB:boolean;
   wRate,bRate:single;
  begin
   inc(estCounter);
   b:=@data[boardIdx];
   // проверка на 3-й повтор
   n:=1;
   j:=b.parent;
   while j>0 do begin
    if CompareBoards(b^,data[j]) then begin
     inc(n);
     if n>=3 then begin
      b.BlackRate:=1;
      b.WhiteRate:=1;
      b.rate:=0;
      b.flags:=b.flags or movRepeat;
      exit;
     end;
    end;
    j:=data[j].parent;
   end;

   // Оценка уже есть в кэше?
   if not noCache then
    if GetCachedRate(b^,hash) then begin
      IsCheck(b^); // флаги шаха нужно вычислить в любом случае (TODO: убрать)
      exit;
     end;

   with b^ do begin
    wRate:=-1000;
    bRate:=-1000;
    flags:=flags and (not movCheck);
    (*if quality=0 then begin
     for i:=0 to 7 do
      for j:=0 to 7 do
       case GetCell(i,j) of
        KingWhite:WhiteRate:=WhiteRate+1000;
        KingBlack:BlackRate:=BlackRate+1000;
       end;
     exit;
    end; *)
    CalcBeatable(b^,beatable);
    // Базовая оценка
    for i:=0 to 7 do
     for j:=0 to 7 do
      case GetCell(i,j) of
       PawnWhite:WhiteRate:=wRate+PawnRate[j];
       PawnBlack:BlackRate:=bRate+PawnRate[7-j];

       RookWhite:wRate:=wRate+5;
       RookBlack:bRate:=bRate+5;
       QueenWhite:wRate:=wRate+9;
       QueenBlack:bRate:=bRate+9;
       BishopWhite:wRate:=wRate+3;
       BishopBlack:bRate:=bRate+3;
       KnightWhite:wRate:=wRate+3;
       KnightBlack:bRate:=bRate+3;
       // если король под шахом и ход противника - игра проиграна
       KingWhite:begin
        // условие инвертировано
        if WhiteTurn or (beatable[i,j] and Black=0) then wRate:=wRate+1005;
        if beatable[i,j] and Black>0 then flags:=flags or movCheck;
       end;
       KingBlack:begin
        if not WhiteTurn or (beatable[i,j] and White=0) then bRate:=bRate+1005;
        if beatable[i,j] and White>0 then flags:=flags or movCheck;
       end;
      end;
    // Бонус за рокировку
    if rFlags and $8>0 then wRate:=wRate+0.8;
    if rFlags and $80>0 then bRate:=bRate+0.8;
    // Штраф за невозможность рокировки
    if (rFlags and $8=0) and (rflags and $4>0) then wRate:=wRate-0.3;
    if (rFlags and $80=0) and (rflags and $40>0) then bRate:=bRate-0.3;

    if gamestage<3 then begin
     // Штраф за невыведенные фигуры
     if GetCell(1,0)=KnightWhite then wRate:=wRate-0.2;
     if GetCell(6,0)=KnightWhite then wRate:=wRate-0.2;
     if GetCell(2,0)=BishopWhite then wRate:=wRate-0.2;
     if GetCell(5,0)=BishopWhite then wRate:=wRate-0.2;
     if GetCell(1,7)=KnightBlack then bRate:=bRate-0.2;
     if GetCell(6,7)=KnightBlack then bRate:=bRate-0.2;
     if GetCell(2,7)=BishopBlack then bRate:=bRate-0.2;
     if GetCell(5,7)=BishopBlack then bRate:=bRate-0.2;
     // штраф за гуляющего короля
     for i:=0 to 7 do
      for j:=1 to 6 do begin
       if GetCell(i,j)=KingWhite then wRate:=wRate-sqr(j)*0.05;
       if GetCell(i,j)=KingBlack then bRate:=bRate-sqr(7-j)*0.05;
      end;
    end;
    // штраф за сдвоенные пешки и бонус за захват открытых линий
    for i:=0 to 7 do begin
     n:=0; m:=0; f:=0;
     for j:=0 to 7 do begin
      if GetCell(i,j)=PawnWhite then inc(n);
      if GetCell(i,j)=PawnBlack then inc(m);
      if GetCell(i,j) in [RookWhite,QueenWhite] then f:=f or 1;
      if GetCell(i,j) in [RookBlack,QueenBlack] then f:=f or 2;
     end;
     if n>1 then wRate:=wRate-0.1*n;
     if m>1 then bRate:=bRate-0.1*m;
     if (n=0) and (m=0) and (f and 1>0) then wRate:=wRate+0.1;
     if (n=0) and (m=0) and (f and 2>0) then bRate:=bRate+0.1;
    end;

    // Надбавка за инициативу
  {  if WhiteTurn then wRate:=wRate+0.1
     else bRate:=bRate+0.05;}

    if not simplifiedMode then begin
     // 1-е расширение оценки - поля и фигуры под боем
     maxblack:=0; maxwhite:=0;
     for i:=0 to 7 do
      for j:=0 to 7 do begin
       v:=0.08;
       if (i in [2..5]) and (j in [2..5]) then v:=0.09;
       if (i in [3..4]) and (j in [3..4]) then v:=0.11;
       if beatable[i,j] and White>0 then wRate:=wRate+v;
       if beatable[i,j] and Black>0 then bRate:=bRate+v;
       // Незащищенная фигура под боем на ходу противника - минус фигуру!
       if (b.whiteTurn) and (beatable[i,j] and White>0) and (GetPieceColor(i,j)=Black) then begin
        if beatable[i,j] and Black>0 then v:=bweight[GetPieceType(i,j)]-bweight2[beatable[i,j] and 7]
         else v:=bweight[GetPieceType(i,j)];
        if maxblack<v then maxblack:=v;
       end;
       if (not b.whiteTurn) and (beatable[i,j] and Black>0) and (GetPieceColor(i,j)=White) then begin
        if beatable[i,j] and White>0 then v:=bweight[GetPieceType(i,j)]-bweight2[(beatable[i,j] shr 3) and 7]
         else v:=bweight[GetPieceType(i,j)];
        if maxWhite<v then maxWhite:=v;
       end;
      end;
     wRate:=wRate-maxWhite;
     bRate:=bRate-maxBlack;
    end;

    if wRate<5.5 then begin // один король
     for i:=0 to 7 do
      for j:=0 to 7 do
       if GetCell(i,j)=KingWhite then begin
        x:=i; y:=j;
        wRate:=wRate-0.2*(abs(i-3.5)+abs(j-3.5));
       end;
     for i:=0 to 7 do
      for j:=0 to 7 do
       if GetCell(i,j)=KingBlack then
        bRate:=bRate-0.05*(abs(i-x)+abs(j-y));
    end;
    if bRate<5.5 then begin // один король
     for i:=0 to 7 do
      for j:=0 to 7 do
       if GetCell(i,j)=KingBlack then begin
        x:=i; y:=j;
        bRate:=bRate-0.2*(abs(i-3.5)+abs(j-3.5));
       end;
     for i:=0 to 7 do
      for j:=0 to 7 do
       if GetCell(i,j)=KingWhite then
        wRate:=wRate-0.05*(abs(i-x)+abs(j-y));
    end;

    whiteRate:=wRate;
    blackRate:=bRate;
    rate:=(wRate-bRate)*(1+10/(bRate+wRate));
  {   rate:=(bRate-wRate)*(1+1/(bRate+wRate))+random(3)/2000
    else
     rate:=(wRate-bRate)*(1+1/(bRate+wRate))+random(3)/2000;}

    // сохранить вычисленную оценку в кэше
    if not noCache then
     CacheBoardRate(hash,rate);

    if PlayerWhite then rate:=-rate;
   end;
  end;

 // Определяет фазу игры: дебют..эндшпиль
 // Фаза влияет на оценку позиции
 procedure DetectGamePhase;
  var
   i,j:integer;
   c:integer;
  begin
   c:=0;
   with data[curBoardIdx] do
    for i:=0 to 7 do begin
     if not CellIsEmpty(i,0) then inc(c);
     if not CellIsEmpty(i,7) then inc(c);
     if GetCell(i,1)=PawnWhite then inc(c);
     if GetCell(i,6)=PawnBlack then inc(c);
    end;
   if c>=18 then begin
    gamestage:=1; exit; // дебют
   end;
   EstimatePosition(curBoardIdx,false,true);
   with curBoard^ do
    if (whiteRate<18) and (blackRate<18) then gameStage:=3
     else gamestage:=2;
  end;

 function MakeTurnFromLibrary:boolean;
  var
   i,j,n,weight,board:integer;
   turns:array[1..30] of integer;
  begin
    n:=0; weight:=0;
    // Составим список вариантов ходов для текущей позиции
    for i:=0 to high(turnLib) do
     if (CompareMem(@curBoard.cells,@turnLib[i].field,sizeof(TField))) and
        (curBoard.whiteTurn=turnLib[i].whiteTurn) then begin
      inc(n);
      turns[n]:=i;
      inc(weight,turnlib[i].weight);
     end;
    if n>0 then begin
     j:=random(weight);
     weight:=0;
     for i:=1 to n do begin
      weight:=weight+turnlib[turns[i]].weight;
      if weight>j then begin
       board:=AddChild(curBoardIdx);
       with turnlib[turns[i]] do
        DoMove(data[board],turnFrom,turnTo);
       moveReady:=board;
       exit;
      end;
     end;
    end;
  end;


(*
 procedure CheckTree(root:integer);
  var
   c:integer;
  begin
   data[root].flags:=data[root].flags or movVerified;
   c:=data[root].firstChild;
   while c>0 do begin
    CheckTree(c);
    Assert(data[c].parent=root);
    c:=data[c].nextSibling;
   end;
  end;

 procedure SortChildren(root:integer);
  var
   children:array[1..120] of integer;
   i,j,d,n,c:integer;
  begin
   n:=0;
   c:=data[root].firstChild;
   if c=0 then exit;
   while c>0 do begin
    inc(n);
    children[n]:=c;
    c:=data[c].nextSibling;
   end;
   for i:=1 to n-1 do
    for j:=i+1 to n do
     if data[children[j]].rate>data[children[i]].rate then begin
      d:=children[i];
      children[i]:=children[j];
      children[j]:=d;
     end;
   c:=children[1];
   data[root].firstChild:=c;
   data[c].prevSibling:=0;
   d:=c;
   for i:=2 to n do begin
    c:=children[i];
    data[c].prevSibling:=d;
    data[d].nextSibling:=c;
    d:=c;
   end;
   data[c].nextSibling:=0;
   data[root].lastChild:=c;
  end;

 // Обрезание дерева
 procedure CutTree(root:integer;p1,p2:integer);
  var
   i,j,d:integer;
   v,v2,gate,gate2:single;
   dir,fl:boolean;
  begin
   SortChildren(root);
  // t1:=p1 div (data[root].depth+p2);
  // t2:=(p1+20) div (data[root].depth+p2-1);

   //dir:=data[root].depth and 1=0;
   dir:=data[root].whiteTurn xor playerWhite;
   if dir then d:=data[root].firstChild
     else d:=data[root].lastChild;

   j:=1; v:=0; gate:=(4+sqr(data[root].depth))/p1; gate2:=gate*0.5;
   v2:=data[root].rate; v:=v2;
   fl:=false;
   while d>0 do begin
    if (abs(data[d].rate-v2)>gate) and fl then
        DeleteNode(d)
      else begin
       CutTree(d,p1,p2);
       gate2:=gate2*0.6+0.01;
      end;
    v:=data[d].rate;
    if dir then d:=data[d].nextSibling else d:=data[d].prevSibling;
    if abs(data[d].rate-v)>gate2 then fl:=true;
    inc(j);
   end;

  end;

(*
 //
 function TThinkThread.ThinkIteration(root:integer;iteration:byte):boolean;
  var
   i,j,c,limit:integer;
   arr:array[1..100] of integer;
  begin
   result:=true;
   case iteration of
    1:begin
     BuildTree(root);
     RateTree(root);
    end;
    2..19:begin
     if data[root].firstChild=data[root].lastChild then begin
      result:=false; exit;
     end;
     limit:=8*(220*level+500);
     if limit>20000 then limit:=20000;
     totalLeafCount:=CountLeaves(root);
     if totalLeafCount>limit then begin
      CutTree(root,8,0);
      totalLeafCount:=CountLeaves(root);
     end;
     if totalLeafCount>limit then begin
      CutTree(root,20,0);
      totalLeafCount:=CountLeaves(root);
     end;
     if totalLeafCount>limit then begin
      CutTree(root,40,0);
      totalLeafCount:=CountLeaves(root);
     end;
     if totalLeafCount>limit then begin
      result:=false; exit;
     end;
     inc(d1); inc(d2);
     if totalLeafCount<limit div 10 then
      BuildTree(root)
     else
      BuildTree(root);
     RateTree(root);
    end;
   end;
  end;

 // Найти ход
 procedure TThinkThread.DoThink;
  var
   startTime,limit:cardinal;
   i,j,n:integer;
   weight:integer;
   b:TBoard;
   color,color2,phase:byte;
   v:single;
   hash:int64;
   fl:boolean;
   beatable:TBeatable;
  begin
   starttime:=gettickcount;

   if PlayerWhite then begin
    color:=Black; color2:=white;
   end else begin
    color:=White; color2:=black;
   end;

   // 1. Поиск ходов в библиотеке
   if useLibrary and MakeTurnFromLibrary then exit;

   // 2. Обдумывание
   // определение фазы игры
   GetGamePhase;

   // 2.1. Составить все различные позиции на 3 полухода вперед
   status:='Составление позиций';
   try
   qStart:=1; // текущий эл-т для обработки
   qlast:=1; // последний добавленный в очередь эл-т
   freecnt:=0;
   for i:=memsize downto 1 do begin
    inc(freecnt);
    freeList[freecnt]:=i;
   end;
   dec(freecnt);
   /// TODO: не портить дерево!
   //data[1]:=board;
   data[1].depth:=0;
   data[1].weight:=26;
   data[1].parent:=0;
   data[1].nextSibling:=0;
   data[1].firstChild:=0;
   data[1].lastChild:=0;
   EstimatePosition(1,10);
   data[1].flags:=0;
  // data[1].flags:=data[1].flags and not movDB;
   cacheUse:=0; cacheMiss:=0;
   estCounter:=0;

   phase:=0;
   if level=0 then begin
    // упрощенный уровень
    BuildTree(1);
    RateTree(1,10);
   end else begin
    // обычный уровень
    case level of
     1:limit:=100000;
     2:limit:=500000;
     3:limit:=2000000;
    end;
    d1:=3; d2:=4;
    for i:=1 to 11 do begin
     phase:=i;
     status:='Фаза '+inttostr(i);
     if not ThinkIteration(1,i) then begin
      dec(phase);
      break;
     end;
     if (plimit>0) and (i>=plimit) then break;
     if (estCounter>limit) or (terminated) then break;
    end;
   end;
   totalLeafCount:=CountLeaves(1);

  { status:='Углублённая проработка';
   BuildTree(1,5,6);
   RateTree(1,false);}
   v:=0;
   if cacheUse>0 then v:=(cacheUse-cacheMiss)/cacheUse;
   status:='Фаз: '+inttostr(phase)+
    '. Поз: '+inttostr(estCounter)+' / '+inttostr(memsize-freeCnt)+
    ' / '+inttostr(totalLeafCount)+
    ', кэш: '+floattostrf(v,ffFixed,3,2)+
    '. Время: '+FloatToStrF((GetTickCount-startTime)/1000,ffFixed,3,1);

   // Выбор оптимального хода
   if data[1].firstChild=0 then begin
    // нет ходов
    CalcBeatable(data[1],beatable);
    gameState:=1; // пат
    for i:=0 to 7 do
     for j:=0 to 7 do
      if (data[1].GetCell(i,j)=King+color) and (beatable[i,j] and color2>0) then
       gameState:=2; // мат
    terminate;
    exit;
   end else begin
    // Ходы есть - выбрать лучший
    i:=data[1].firstChild;
    j:=i;
    while i>0 do begin
     if data[i].rate=data[1].rate then begin
      j:=i; break;
     end;
     i:=data[i].nextSibling;
    end;
   end;

   if abs(data[j].rate)>100 then status:=status+' МАТ';

   // Обновить базу
   if selfTeach then begin
    LoadRates;
    hash:=BoardHash(data[1]);
    fl:=true;
    for i:=0 to length(dbItems)-1 do
     if dbItems[i].hash=hash then begin
      dbItems[i].rate:=round(data[j].rate*1000) shl 8;
      fl:=false;
      break;
     end;
    if fl then begin
     i:=length(dbItems);
     setLength(dbItems,i+1);
     dbItems[i].hash:=hash;
     dbItems[i].rate:=round(data[j].rate*1000) shl 8;
    end;
    SaveRates;
   end;

   moveReady:=j;
   except
    on e:exception do ErrorMessage(e.message);
   end;

  end;

 procedure TThinkThread.Execute;
  begin
  // fillchar(cache,sizeof(cache),0);
   running:=true;
   if selfTeach then LoadRates;
   repeat
    if (moveReady<0) and (gameState=0) and (curBoard.whiteTurn xor playerWhite) then
     DoThink
    else
     sleep(9); // Если ход не наш - ничего не делать
   until terminated;
   running:=false;
  end;

  *)

 // Корректирует вес поддерева, добавляет позиции с положительным весом в список активных
 procedure AddWeight(node,add:integer);
  begin
   inc(data[node].weight,add);
   ASSERT(data[node].weight>-50);
   if data[node].firstChild>0 then begin
    node:=data[node].firstChild;
    while node>0 do begin
     AddWeight(node,add);
     node:=data[node].nextSibling;
    end;
   end else
    if data[node].weight>0 then
     active.Add(node);
  end;

 // Проходит по дереву и вычисляет оценки у позиций, имеющих продолжение
 // вызывается только для позиций, имеющих продолжение
 // Возвращает кол-во потомков у ноды
 function RateSubtree(node:integer):integer;
  var
   i,d:integer;
   best,v:single;
   mode:boolean;
  begin
   result:=1;
   mode:=data[node].whiteTurn xor playerWhite; // что вычислять: минимум или максимум
   d:=data[node].firstChild;
   if data[d].firstChild>0 then inc(result,RateSubtree(d));
   best:=data[d].rate;
   d:=data[d].nextSibling;
   while d>0 do begin
    if data[d].firstChild>0 then inc(result,RateSubtree(d))
     else inc(result);
    v:=data[d].rate;
    if mode then begin
     if v>best then best:=v;
    end else begin
     if v<best then best:=v;
    end;
    d:=data[d].nextSibling;
   end;
   data[node].rate:=best;
   data[node].children:=result;
  end;

 procedure RateTree;
  var
   time:int64;
  begin
   time:=MyTickCount;
   curBoard.children:=0;
   if curBoard.firstChild>0 then RateSubtree(curBoardIdx);
   time:=MyTickCount-time;
  end;

 // Добавляет дочерние узлы для всех возможных продолжений указанной позиции
 procedure ExtendNode(node:integer);
  var
   i,j,k,color,newNode,cellFrom:integer;
   moves:TMovesList;
   toAdd:array[0..255] of integer;
   toAddCnt:integer;
  begin
   with data[node] do begin
    // не продолжать позиции, которые:
    // - являются проигрышными для одной из сторон
    // - являются патовой ситуацией из-за повторения позиций
    // - с оценкой из базы при низком весе
    if (flags and movGameOver>0) then exit;
    if (flags and movDB>0) and (weight<12) then exit;

    if WhiteTurn then color:=White else color:=Black;
   end;

   // продолжить дерево
   toAddCnt:=0;
   for i:=0 to 7 do
    for j:=0 to 7 do begin
      if data[node].GetPieceColor(i,j)<>color then continue;
      cellFrom:=i+j shl 4;
      GetAvailMoves(data[node],cellFrom,moves);
      for k:=1 to moves[0] do begin
       newNode:=AddChild(node);
       if newNode=0 then exit; // закончилась память
       DoMove(data[newNode],cellFrom,moves[k]);
       EstimatePosition(newNode,false);
       with data[newNode] do begin
        if abs(rate)>200 then begin // недопустимый ход?
         DeleteNode(newNode,true);
         continue;
        end;
        // скорректируем вес
        if flags and movBeat>0 then weight:=weight+4
        else
        if flags and movCheck>0 then weight:=weight+7;

        if weight<=0 then continue; // позиция не заслуживает продолжения
       end;
       toAdd[toAddCnt]:=newNode;
       inc(toAddCnt);
      end;
    end;
   if toAddCnt>0 then active.Add(@toAdd,toAddCnt);
  end;

 // Поток занимается исключительно развитием дерева поиска:
 // - достаёт из кучи позицию с наибольшим весом
 // - строит все возможные варианты продолжения и оценивает полученные позиции; обновляет оценки предков в дереве
 // - заносит в кучу полученные позиции, если они нуждаются в продолжении
 procedure TThinkThread.Execute;
  var
   node:integer;
  begin
   counter:=0;
   waitCounter:=0;
   threadRunning:=true;
   try
   repeat
    if not running then begin // no work to do
     idle:=true;
     Sleep(1); continue;
    end;
    idle:=false;

    node:=active.Get;
    if node=0 then begin // список пуст - работы нет
     inc(waitCounter);
     Sleep(1);
     continue;
    end;
    ExtendNode(node);
    inc(counter);

   until terminated;
   except
    on e:Exception do ErrorMessage('Error: '+ExceptionMsg(e));
   end;
   threadRunning:=false;
  end;

 // Рекурсивный обход дерева: находим листья, вычисляем их веса и заносим в список активных
 procedure ProcessTree(node,baseWeight:integer;baseRate:single);
  var
   w:integer;
  begin
   if data[node].firstChild>0 then begin
    // есть потомки
    node:=data[node].firstChild;
    while node>0 do begin
     ProcessTree(node,baseWeight-8,baseRate);
     node:=data[node].nextSibling;
    end;
   end else begin
    // узел - лист: вычислить вес и добавить в список активных
    with data[node] do begin
     if flags and movGameOver>0 then exit; // конец игры, нельзя продолжить
     w:=baseWeight;//+round(rate-baseRate); // если у позиции высокая оценка - она продолжается в первую очередь
     if w>0 then begin
      weight:=w;
      active.Add(node);
     end;
    end;
   end;
  end;

 // Подрезка дерева: удаляются незначимые ветки
 procedure CutTree;
  begin

  end;

 //
 procedure UpdateJob;
  begin

  end;

 // Запускается однократно при старте AI. Очищает дерево поиска.
 // Начинает строить дерево поиска. А контролировать работу будет таймер.
 procedure StartThinking;
  var
   i,w:integer;
   time:int64;
   node:integer;
  begin
   time:=MyTickCount;
   startTime:=time;
   secondsElapsed:=-1;
   startEstCounter:=estCounter;
   DetectGamePhase;

   // удалить любых потомков curBoard (если есть)
   DeleteChildrenExcept(curBoardIdx,0);

   active.Clear;
   // базовый начальный вес
   case aiLevel of
    1:w:=25;
    2:w:=28;
    3:w:=31;
    4:w:=34;
   end;
   curBoard.weight:=w;
   active.Add(curBoardIdx);

   time:=MyTickCount-time;
   LogMessage('StartThinking time = %d',[time]);
  end;

 // Раз в секунду обновляет отображаемый статус AI
 procedure UpdateStats;
  var
   i:integer;
   time:int64;
  begin
   // Статистика
   time:=MyTickCount;
   i:=round((time-startTime)/1000);
   if i<>secondsElapsed then begin
    secondsElapsed:=i;
    aiStatus:=Format('Прошло: %d c, позиций: %s, оценок: %s',
     [secondsElapsed,FormatInt(memSize-freeCnt),FormatInt(estCounter-startEstCounter)]);
    // Кол-во оценок в секунду:

    if lastStatTime>0 then begin
     i:=1000*(estCounter-lastEstCounter) div (time-lastStatTime);
     if i>0 then LogMessage('Rate: %d positions/sec',[i]);
    end;
    lastEstCounter:=estCounter;
    lastStatTime:=time;
   end;
  end;

 // Таймер вызывается из главного потока.
 // Он приостанавливает AI, анализирует положение и вносит корректировки для продолжения работы
 procedure AiTimer;
  var
   time:int64;
  begin
   if not started or not running then exit;
   PauseAI;
   try
    time:=MyTickCount;
    UpdateStats;
    // Возможные состояния:
    // 1) нет активных элементов (работа выполнена)
    // 2) закончилась память
    if (active.count=0) or (freeCnt<100) then begin
     RateTree;
     if freeCnt<100 then CutTree;
     UpdateJob;
    end;

    time:=MyTickCount-time;
    if time>10 then LogMessage('Timer spent %d ms',[time]);
   except
    on e:Exception do LogMessage('Error in timer: '+ExceptionMsg(e));
   end;
   ResumeAI;
  end;

 // Игрок сделал ход: значит curBoard уже указывает на одного из потомков дерева поиска
 // Нужно удалить из дерева лишние ветки, обновить веса и продолжить поиск в текущей ветке
 procedure PlayerMadeTurn;
  var
   cnt:integer;
  begin
   if not started then exit;
   // удаление ненужных веток
   cnt:=freeCnt;
   DeleteChildrenExcept(curBoard.parent,curBoardIdx);
   cnt:=FreeCnt-cnt;
   LogMessage('Deleting branches: %d nodes freed',[cnt]);
   ResumeAI;
  end;

 // Инициализация AI
 procedure StartAI;
  var
   i,n:integer;
   sysInfo:TSystemInfo;
  begin
   if started then exit;
   // Создать потоки
   GetSystemInfo(sysInfo);
   n:=sysInfo.dwNumberOfProcessors;
   if n>=4 then dec(n);
   if n>=6 then dec(n);
   {$IFDEF SINGLETHREADED}
   n:=1;
   {$ENDIF}
   SetLength(threads,n);
   for i:=0 to high(threads) do begin
    threads[i]:=TThinkThread.Create;
    threads[i].id:=i;
   end;

   active.Init;
   LogMessage('AI started');

   started:=true;
   StartThinking;
   ResumeAI;
   LogMessage('AI running');
  end;

 procedure ResumeAI;
  var
   i:integer;
  begin
   if not started then begin
    LogMessage('Can''t resume: not started');
    exit;
   end;
   if running then exit;
   running:=true;
  end;

 procedure PauseAI;
  var
   i:integer;
   wait:boolean;
  begin
   if not started or not running then exit;
   running:=false;
   // Подождать пока все потоки реально остановятся
   repeat
    wait:=false;
    for i:=0 to high(threads) do
     if not threads[i].idle then wait:=true;
    if wait then
     sleep(0)
    else
     break;
   until false;
   Sleep(0);
  end;

 procedure StopAI;
  var
   i:integer;
  begin
   if not started then exit;
   PauseAI;
   LogMessage('AI paused');

   for i:=0 to high(threads) do begin
    threads[i].Terminate;
    FreeAndNil(threads[i]);
   end;
   started:=false;
   LogMessage('AI stopped');
  end;

 function IsAIrunning:boolean;
  begin
   result:=running;
  end;

 function IsAiStarted:boolean;
  begin
   result:=started;
  end;

{ TBaskets }

procedure TBaskets.Init;
 var
  i:integer;
 begin
  lock:=0;
  SetLength(links,memSize);
  Clear;
 end;

procedure TBaskets.Add(boards:PInteger; count:integer);
 begin
  SpinLock(lock);
  while count>0 do begin
   InternalAdd(boards^);
   dec(count);
   inc(boards);
  end;
  Unlock(lock);
 end;

procedure TBaskets.Clear;
 begin
  SpinLock(lock);
  ZeroMem(baskets,sizeof(baskets));
  count:=0;
  lastBasket:=0;
  Unlock(lock);
 end;

procedure TBaskets.Add(b: integer);
 begin
  SpinLock(lock);
  InternalAdd(b);
  Unlock(lock);
 end;

procedure TBaskets.InternalAdd(idx:integer);
 var
  weight:byte;
 begin
  weight:=data[idx].weight;
  ASSERT(weight>0);
  with baskets[weight] do begin
   if last>0 then links[last]:=idx;
   last:=idx;
   if first=0 then first:=idx;
  end;
  if weight>lastBasket then
   lastBasket:=weight;
  inc(count);
 end;

function TBaskets.Get:integer;
 var
  w:byte;
 begin
  SpinLock(lock);
  if lastBasket=0 then begin
   Unlock(lock);
   exit(0);
  end;
  with baskets[lastBasket] do begin
   result:=first;
   dec(self.count);
   if first=last then begin
    first:=0; last:=0;
    // корзина пуста - перейти к следующей
    repeat
     dec(lastBasket);
    until (lastBasket=0) or (baskets[lastBasket].first>0);
   end else
    first:=links[result];
  end;
  Unlock(lock);
 end;

 procedure AiPerfTest;
  var
   i:integer;
   t1:single;
  begin
   StartMeasure(1);
   for i:=1 to 300000 do
    EstimatePosition(curBoardIdx,false,true);
   t1:=EndMeasure(1);
   ShowMessage(Format('EstimatePosition = %3.2f',[t1]),'Performance');
  end;

end.
