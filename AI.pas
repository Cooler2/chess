﻿// Здесь реализация алгоритма принятия решений
unit AI;
interface
 var
  useLibrary:boolean=false;
  turnTimeLimit:integer = 5; // turn time limit in seconds
  aiLevel:integer; // уровень сложности (1..5) - определяет момент, когда AI принимает решение о готовности хода
  aiSelfLearn:boolean=true; // режим самообучения: пополняет базу оценок позиций в ходе игры

  aiStatus:string; // состояние работы AI
  moveReady:integer; // готовность хода - индекс выбранной доски продолжения (<=0 - ход не готов). Когда выставляется - AI ставится на паузу

 procedure StartAI;
 procedure PauseAI;
 procedure ResumeAI;
 procedure StopAI;
 procedure AiTimer; // необходимо вызывать регулярно не менее 20 раз в секунду. Переключает режим работы AI

 function IsAIrunning:boolean;
 procedure EstimatePosition(boardIdx:integer;quality:byte;noCache:boolean=false);


implementation
 uses Apus.MyServis,SysUtils,Classes,gamedata,logic;

 const
  // штраф за незащищенную фигуру под боем
  bweight:array[0..6] of single=(0,1, 5.2, 3.1, 3.1, 9.3, 1000);
  bweight2:array[0..6] of single=(0,1, 3.1, 3.1, 5.2, 9.3, 1000);

 type
  TThinkThread=class(TThread)
   status:string;
   useLibrary,advSearch,selfTeach,running:boolean;
   level,plimit,d1,d2:byte;
   procedure Reset;
   procedure Execute; override;
   function ThinkIteration(root:integer;iteration:byte):boolean;
   procedure DoThink;
  end;

 var
  threads:array[0..15] of TThinkThread;


 // оценка позиции (rate - за черных)
 procedure EstimatePosition(boardIdx:integer;quality:byte;noCache:boolean=false);
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

   if not noCache then begin
    inc(cacheUse);
    hash:=BoardHash(b^);
    h:=hash and CacheMask;
    if cache[h].hash=hash then
     with b^ do begin
      // вычисление флага шаха
      IsCheck(b^);
      whiterate:=1;
      blackrate:=1;
      rate:=integer(cache[h].rate and $FFFFFF00)/(1000*256);
      if cache[h].rate and 1>0 then flags:=flags or movDB;
      if PlayerWhite then rate:=-rate;
      exit;
     end;
   end;

   with b^ do begin
    whiteRate:=-1000;
    blackRate:=-1000;
    flags:=flags and (not movCheck);
    if quality=0 then begin
     for i:=0 to 7 do
      for j:=0 to 7 do
       case GetCell(i,j) of
        KingWhite:WhiteRate:=WhiteRate+1000;
        KingBlack:BlackRate:=BlackRate+1000;
       end;
     exit;
    end;
    CalcBeatable(b^,beatable);
    // Базовая оценка
    for i:=0 to 7 do
     for j:=0 to 7 do
      case GetCell(i,j) of
       PawnWhite:WhiteRate:=WhiteRate+PawnRate[j];
       PawnBlack:BlackRate:=BlackRate+PawnRate[7-j];

       RookWhite:WhiteRate:=WhiteRate+5;
       RookBlack:BlackRate:=BlackRate+5;
       QueenWhite:WhiteRate:=WhiteRate+9;
       QueenBlack:BlackRate:=BlackRate+9;
       BishopWhite:WhiteRate:=WhiteRate+3;
       BishopBlack:BlackRate:=BlackRate+3;
       KnightWhite:WhiteRate:=WhiteRate+3;
       KnightBlack:BlackRate:=BlackRate+3;
       // если король под шахом и ход противника - игра проиграна
       KingWhite:begin
        // условие инвертировано
        if WhiteTurn or (beatable[i,j] and Black=0) then WhiteRate:=WhiteRate+1005;
        if beatable[i,j] and Black>0 then flags:=flags or movCheck;
       end;
       KingBlack:begin
        if not WhiteTurn or (beatable[i,j] and White=0) then BlackRate:=BlackRate+1005;
        if beatable[i,j] and White>0 then flags:=flags or movCheck;
       end;
      end;
    // Бонус за рокировку
    if rFlags and $8>0 then WhiteRate:=WhiteRate+0.8;
    if rFlags and $80>0 then BlackRate:=BlackRate+0.8;
    // Штраф за невозможность рокировки
    if (rFlags and $8=0) and (rflags and $4>0) then WhiteRate:=WhiteRate-0.3;
    if (rFlags and $80=0) and (rflags and $40>0) then BlackRate:=BlackRate-0.3;

    if gamestage<3 then begin
     // Штраф за невыведенные фигуры
     if GetCell(1,0)=KnightWhite then WhiteRate:=WhiteRate-0.2;
     if GetCell(6,0)=KnightWhite then WhiteRate:=WhiteRate-0.2;
     if GetCell(2,0)=BishopWhite then WhiteRate:=WhiteRate-0.2;
     if GetCell(5,0)=BishopWhite then WhiteRate:=WhiteRate-0.2;
     if GetCell(1,7)=KnightBlack then BlackRate:=BlackRate-0.2;
     if GetCell(6,7)=KnightBlack then BlackRate:=BlackRate-0.2;
     if GetCell(2,7)=BishopBlack then BlackRate:=BlackRate-0.2;
     if GetCell(5,7)=BishopBlack then BlackRate:=BlackRate-0.2;
     // штраф за гуляющего короля
     for i:=0 to 7 do
      for j:=1 to 6 do begin
       if GetCell(i,j)=KingWhite then WhiteRate:=WhiteRate-sqr(j)*0.05;
       if GetCell(i,j)=KingBlack then BlackRate:=BlackRate-sqr(7-j)*0.05;
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
     if n>1 then WhiteRate:=WhiteRate-0.1*n;
     if m>1 then BlackRate:=BlackRate-0.1*m;
     if (n=0) and (m=0) and (f and 1>0) then WhiteRate:=WhiteRate+0.1;
     if (n=0) and (m=0) and (f and 2>0) then BlackRate:=BlackRate+0.1;
    end;

    // Надбавка за инициативу
  {  if WhiteTurn then WhiteRate:=WhiteRate+0.1
     else BlackRate:=BlackRate+0.05;}

    if quality>0 then begin
     // 1-е расширение оценки - поля и фигуры под боем
     maxblack:=0; maxwhite:=0;
     for i:=0 to 7 do
      for j:=0 to 7 do begin
       v:=0.08;
       if (i in [2..5]) and (j in [2..5]) then v:=0.09;
       if (i in [3..4]) and (j in [3..4]) then v:=0.11;
       if beatable[i,j] and White>0 then WhiteRate:=WhiteRate+v;
       if beatable[i,j] and Black>0 then BlackRate:=BlackRate+v;
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
     whiteRate:=whiteRate-maxWhite;
     blackRate:=blackRate-maxBlack;
    end;

    if whiteRate<5.5 then begin // один король
     for i:=0 to 7 do
      for j:=0 to 7 do
       if GetCell(i,j)=KingWhite then begin
        x:=i; y:=j;
        WhiteRate:=WhiteRate-0.2*(abs(i-3.5)+abs(j-3.5));
       end;
     for i:=0 to 7 do
      for j:=0 to 7 do
       if GetCell(i,j)=KingBlack then
        BlackRate:=BlackRate-0.05*(abs(i-x)+abs(j-y));
    end;
    if BlackRate<5.5 then begin // один король
     for i:=0 to 7 do
      for j:=0 to 7 do
       if GetCell(i,j)=KingBlack then begin
        x:=i; y:=j;
        BlackRate:=BlackRate-0.2*(abs(i-3.5)+abs(j-3.5));
       end;
     for i:=0 to 7 do
      for j:=0 to 7 do
       if GetCell(i,j)=KingWhite then
        WhiteRate:=WhiteRate-0.05*(abs(i-x)+abs(j-y));
    end;

    rate:=(WhiteRate-BlackRate)*(1+10/(BlackRate+WhiteRate));
  {   rate:=(BlackRate-WhiteRate)*(1+1/(BlackRate+WhiteRate))+random(3)/2000
    else
     rate:=(WhiteRate-BlackRate)*(1+1/(BlackRate+WhiteRate))+random(3)/2000;}

    if not noCache then begin
     cache[h].hash:=hash;
     cache[h].rate:=round(rate*1000) shl 8;
     inc(cacheMiss);
    end;

    if PlayerWhite then rate:=-rate;
   end;
  end;


 // Построить полное дерево до заданной глубины
 // продолжать ходы со взятием и шахами, но не далее чем до maxdepth
 // корневой эл-т должен быть оценен!
 procedure BuildTree(root:integer;forHuman:boolean=false);
  var
   i,j,k,newidx,h,cur:integer;
   hash:int64;
   color:byte;
   moves:TMovesList;
  begin
   qstart:=1; qLast:=2;
   qu[qstart]:=root;
   repeat
    cur:=qu[qStart];
    with data[cur] do begin
     // не продолжать позиции, которые:
     // - являются проигрышными для одной из сторон
     // - уже имеют потомков, т.е. были обработаны ранее
     // - приводят к пату из-за повторения позиций
     // - с оценкой из базы
     if (rate>-200) and (rate<200) and (flags and (movRepeat+movDB)=0) then begin
      if firstChild>0 then begin
       k:=firstChild;
       while k>0 do begin
        qu[qLast]:=k;
        inc(qLast);
        k:=data[k].nextSibling;
       end;
       inc(qStart); continue;
      end;
      if weight<=0 then begin
       inc(qStart);
       continue;
      end;
      if (flags and movCheck>0) then begin
       if whiteTurn xor playerWhite then rate:=-300 else rate:=300; /// TODO: check
       //if depth and 1=0 then rate:=-300+depth else rate:=300-depth;
      end else rate:=0; // оценка будет сформирована из потомков, если их нет - пат=0
      if WhiteTurn then color:=White else color:=Black;
      // продолжить дерево
      for i:=0 to 7 do
       for j:=0 to 7 do
        if GetPieceColor(i,j)=color then begin
         GetAvailMoves(data[cur],i+j shl 4,moves);
         for k:=1 to moves[0] do begin
          if freecnt<1 then break;
          newidx:=AddChild(cur);
          DoMove(data[newidx],i+j shl 4,moves[k]);
          qu[qLast]:=newidx;
          inc(qLast);
          EstimatePosition(newidx,10);
          if data[newidx].flags and movBeat>0 then
           data[newidx].weight:=weight-6
          else
          if data[newidx].flags and movCheck>0 then
           data[newidx].weight:=weight-2
          else
           data[newidx].weight:=weight-10;
          if abs(data[newidx].rate)>200 then begin
           // недопустимый ход
           DeleteNode(newidx,true);
           dec(qLast);
          end;
         end;
        end;
     end;
    end;
    inc(qStart);
   until qStart=qLast;
  end;

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

 procedure RateTree(root:integer;leafweight:shortint=10;delbad:boolean=false);
  var
   children:array[1..120] of integer;
   i,d,n,c:integer;
   min,max,v:single;
  begin
   d:=data[root].firstChild;
   n:=0;
   while d>0 do begin
    inc(n);
    if data[d].firstChild>0 then
     RateTree(d,leafweight,delbad)
    else
     data[d].Weight:=leafWeight;
    children[n]:=d;
    d:=data[d].nextSibling;
   end;
   if n=0 then exit;
   min:=data[children[1]].rate;
   max:=min;
   for i:=2 to n do begin
    v:=data[children[i]].rate;
    if v>max then max:=v;
    if v<min then min:=v;
   end;
   if data[root].depth and 1=0 then
    data[root].rate:=max
   else
    data[root].rate:=min;

  { if delbad then begin
    // прореживание дерева
    c:=n;
    if data[root].depth and 1=0 then begin
     v:=(max+min)/2;
     while c>(25 div (data[root].depth+2)) do begin
      for i:=1 to n do
       if (children[i]>0) and (data[children[i]].rate<v) then begin
        DeleteNode(children[i]); children[i]:=0; dec(c);
       end;
      v:=(v*3+max)/4;
     end;
    end else begin
     v:=(max+min)/2;
     while c>(25 div (data[root].depth+2)) do begin
      for i:=1 to n do
       if (children[i]>0) and (data[children[i]].rate>v) then begin
        DeleteNode(children[i]); children[i]:=0; dec(c);
       end;
      v:=(v*3+min)/4;
     end;
    end;
   end; }
  end;

 procedure GetGamePhase;
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
   EstimatePosition(curBoardIdx,10,true);
   with curBoard^ do
    if (whiteRate<18) and (blackRate<18) then gameStage:=3
     else gamestage:=2;
  end;

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

 procedure TThinkThread.Reset;
  begin
   moveReady:=-1;
   gameState:=0;
   useLibrary:=true;
  end;

 procedure AiTimer;
  begin

  end;

 procedure StartAI;
  begin

   ResumeAI;
  end;

 procedure PauseAI;
  begin

  end;

 procedure ResumeAI;
  begin

  end;

 procedure StopAI;
  begin
   PauseAI;

  end;

 function IsAIrunning:boolean;
  begin
   result:=false;
  end;

end.
