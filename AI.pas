// Здесь реализация алгоритма принятия решений
unit AI;
interface
 var
  useLibrary:boolean=false; // разрешение использовать библиотеку дебютов
  turnTimeLimit:integer = 5; // turn time limit in seconds
  aiLevel:integer; // уровень сложности (1..4) - определяет момент, когда AI принимает решение о готовности хода
  aiSelfLearn:boolean=true; // режим самообучения: пополняет базу оценок позиций в ходе игры
  aiUseDB:boolean=true; // можно ли использовать БД оценок позиций
  aiMultithreadedMode:boolean=true;

  aiStatus:string; // строка состояния работы AI
  moveReady:integer; // готовность хода - индекс выбранной доски продолжения (<=0 - ход не готов). Когда выставляется - AI ставится на паузу

 // Все эти процедуры вызываются из главного потока
 procedure StartAI; // Обнуляет рабочие данные и запускает AI в фоновых потоках
 procedure PauseAI;  // Переводит потоки AI в состояние ожидания. После этого можно изучать дерево.
 procedure ResumeAI; // Выводит потоки AI из состояния ожидания в рабочее состояние.
 procedure StopAI; // Останавливает и удаляет потоки.
 procedure PauseAfterThisStage(b:boolean); // запрос паузы AI после завершения текущей фазы (чтобы видеть дерево не в промежуточном состоянии)
 function IsPausedAfterStage:boolean; // true - AI встал на паузу после завершения фазы согласно запросу
 procedure AiTimer; // необходимо вызывать регулярно не менее 20 раз в секунду. Переключает режим работы AI
 procedure PlayerMadeTurn; // сообщает AI о том, что игрок сделал ход (вызывать в состоянии паузы)
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
  bweight:array[0..6] of single=(0,1, 5.2, 3.1, 3.1, 9.3, 250);
  bweight2:array[0..6] of single=(0,1, 3.1, 3.1, 5.2, 9.3, 250);

 type
  // Корзина - содержит элементы с одинаковым приоритетом
  TBasket=record
   first,last:integer;
  end;
  // Реализация приоритетной очереди, используемой для обхода/построения дерева поиска в ширину
  // Представляет собой массив корзин - односвязных списков, содержащих элементы с одинаковым приоритетом
  // Это позволяет выполнять операции Add/Get в среднем за O(1)
  TBaskets=record
   links:array of integer; // связи (односвязный список)
   baskets:array[0..127] of TBasket; // weight должен быть в этих пределах
   lock:NativeInt;
   lastBasket:integer;
   count:integer;
   procedure Init;
   procedure Clear;
   // Нельзя добавлять один и тот же элемент дважды!
   procedure Add(b:integer); overload;
   procedure Add(boards:PInteger;count:integer); overload;
   function Get:integer;
  private
   procedure InternalAdd(idx:integer); inline;
  end;

  // Поток AI
  TThinkThread=class(TThread)
   id:integer;
   threadRunning,idle:boolean;
   counter,waitCounter:integer;
   constructor Create(id:integer);
   procedure Execute; override;
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
  workingThreads:NativeInt;
  // список активных листьев - приоритетная очередь
  active:TBaskets;

  stopAfterStage:integer=50; // запрос остановки поиска после фазы
  stage:integer;
  pausedAfterStage:boolean;

  // Для статистики
  startTime:int64; // время начала хода
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

 procedure PauseAfterThisStage(b:boolean);
  begin
   if b then begin
    stopAfterStage:=stage;
    LogMessage('Request pause after stage %d',[stage]);
   end else begin
    stopAfterStage:=100;
   end;
  end;

 function IsPausedAfterStage:boolean;
  begin
   result:=pausedAfterStage;
   if result then begin
    PauseAI;
    ASSERT(active.count=0);
    LogMessage('Really paused');
    pausedAfterStage:=false;
   end;
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

{   // Оценка уже есть в кэше?
   if not noCache then
    if GetCachedRate(b^,hash) then begin
      IsCheck(b^); // флаги шаха нужно вычислить в любом случае (TODO: избавиться)
      exit;
     end;}

   with b^ do begin
    wRate:=-300;
    bRate:=-300;
    flags:=flags and (not movCheck);
    CalcBeatable(b^,beatable);
    // Базовая оценка
    for i:=0 to 7 do
     for j:=0 to 7 do
      case GetCell(i,j) of
       PawnWhite:wRate:=wRate+PawnRate[j];
       PawnBlack:bRate:=bRate+PawnRate[7-j];

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
        if WhiteTurn or (beatable[i,j] and Black=0) then wRate:=wRate+305;  // останется 5 за короля не под боем
        if beatable[i,j] and Black>0 then flags:=flags or movCheck;
       end;
       KingBlack:begin
        if not WhiteTurn or (beatable[i,j] and White=0) then bRate:=bRate+305;
        if beatable[i,j] and White>0 then flags:=flags or movCheck;
       end;
      end;

    if gamestage<3 then begin // блок оценок, неактуальных в эндшпиле
     // Бонус за рокировку
     if rFlags and $8>0 then wRate:=wRate+0.8;
     if rFlags and $80>0 then bRate:=bRate+0.8;
     // Штраф за невозможность рокировки
     if (rFlags and $8=0) and (rflags and $4>0) then wRate:=wRate-0.3;
     if (rFlags and $80=0) and (rflags and $40>0) then bRate:=bRate-0.3;

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
     i:=wKingPos and 15;
     j:=wKingPos shr 4;
     if (j>0) and (j<7) then wRate:=wRate-j*0.25;
     i:=bKingPos and 15;
     j:=bKingPos shr 4;
     if (j>0) and (j<7) then bRate:=bRate-(7-j)*0.25;
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

    if wRate<6.5 then begin // у белых один король - держаться поближе к центру и подальше от чёрного короля
      x:=wKingPos and $F;
      y:=wKingPos shr 4;
      wRate:=wRate-0.2*(abs(i-3.5)+abs(j-3.5));
      i:=bKingPos and $F;
      j:=bKingPos shr 4;
      bRate:=bRate-0.15*(abs(i-x)+abs(j-y));
    end;
    if bRate<6.5 then begin // у чёрных один король - держаться поближе к центру и подальше от белого короля
      x:=bKingPos and $F;
      y:=bKingPos shr 4;
      bRate:=bRate-0.2*(abs(i-3.5)+abs(j-3.5));
      i:=wKingPos and $F;
      j:=wKingPos shr 4;
      wRate:=wRate-0.15*(abs(i-x)+abs(j-y));
      if wRate<6 then begin // одни короли - ничья
       wRate:=1; bRate:=1;
       flags:=flags or movStalemate;
      end;
    end;

    whiteRate:=wRate;
    blackRate:=bRate;
    rate:=(wRate-bRate)*(1+10/(bRate+wRate));

    if (wRate<-200) or (bRate<-200) then begin
     flags:=flags or movCheckmate;
    end;

    // сохранить вычисленную оценку в кэше
    if not noCache then
     CacheBoardRate(hash,rate,boardIdx);

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

 // Корректирует вес поддерева, добавляет позиции с положительным весом в список активных
 procedure AddWeight(node,add:integer);
  var
   oldWeight:integer;
  begin
   oldWeight:=data[node].weight;
   ASSERT((add>=0) and (add<16));
   inc(data[node].weight,add);
   ASSERT((data[node].weight>-20) and (data[node].weight<200),'Node: '+inttostr(node));
   if data[node].firstChild>0 then begin
    node:=data[node].firstChild;
    while node>0 do begin
     AddWeight(node,add);
     node:=data[node].nextSibling;
    end;
   end else
    if {(oldWeight<=0) and} (data[node].weight>0) then
     active.Add(node);
  end;

 // Проходит по дереву и вычисляет оценки у позиций
 // Обновляет качество оценок
 // Возвращает сколько качества нужно прибавить предку
 function RateSubtree(node:integer):single;
  const
   QUALITY_FADE = 0.5;
  var
   i,d:integer;
   best,v:single;
   mode:boolean;
  begin
   with data[node] do begin
    d:=firstChild;
    if d=0 then begin // лист без потомков
     if flags and movRated=0 then begin
      result:=quality;
      flags:=flags or movRated;
     end else
      result:=0;
     exit;
    end;
    // Есть потомки: вычислить оценку
    result:=0;
    mode:=whiteTurn xor playerWhite; // что вычислять: минимум или максимум
    if d>0 then begin
     result:=result+RateSubtree(d)*QUALITY_FADE;
     best:=data[d].rate;
     d:=data[d].nextSibling;
     while d>0 do begin
      result:=result+RateSubtree(d)*QUALITY_FADE;
      v:=data[d].rate;
      if mode then begin
       if v>best then best:=v;
      end else begin
       if v<best then best:=v;
      end;
      d:=data[d].nextSibling;
     end;
    end;
    flags:=flags or movRated;
    quality:=quality+result;
    rate:=best;
   end;
  end;

 // Если в библиотеке есть ходы для текущей позиции - увеличим оценку таким ходам в дереве чтобы
 // повысить вероятность их выбора на текущей стадии или хотя бы увеличить глубину просмотра
 procedure AdjustRatesUsingLibrary;
  var
   i,n:integer;
   st:string;
   v:single;
  begin
   n:=curBoard.firstChild;
   while n>0 do begin
    for i:=0 to high(turnLib) do
     if turnLib[i].CompareWithBoard(data[n]) then begin
      v:=0.01*random(turnLib[i].weight);
      data[n].rate:=data[n].rate+v;
      st:=st+Format(' %s +%.2f;',[data[n].LastTurnAsString,v]);
      break;
     end;
    n:=data[n].nextSibling;
   end;
   if st<>'' then LogMessage('Library turns promoted:'+st);
  end;

 procedure RateTree;
  var
   time:int64;
  begin
   // VerifyTree; // только в однопоточном режиме!
   time:=MyTickCount;
   if curBoard.firstChild>0 then begin
    curBoard.quality:=curBoard.quality+RateSubtree(curBoardIdx);
   end;
   if IsMyTurn and (curboard.depth<10) then
    AdjustRatesUsingLibrary;
   time:=MyTickCount-time;
   if time>100 then LogMessage('RateTree time: %d',[time]);
  end;

 // Добавляет дочерние узлы для всех возможных продолжений указанной позиции
 procedure ExtendNode(node:integer);
  var
   i,j,k,color,newNode,cellFrom:integer;
   moves:TMovesList;
   toAdd:array[0..255] of integer;
   toAddCnt,cnt:integer;
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
   cnt:=0; // кол-во доступных ходов, втч таких, которые не будут продолжены
   for i:=0 to 7 do
    for j:=0 to 7 do begin
      if data[node].GetPieceColor(i,j)<>color then continue;
      cellFrom:=i+j shl 4;
      GetAvailMoves(data[node],cellFrom,moves);

      for k:=1 to moves[0] do begin
       newNode:=AddChild(node);
       if newNode=0 then exit; // закончилась память
       DoMove(data[newNode],cellFrom,moves[k]);
       // TODO: нет смысла детально оценивать ноды, которые будут продолжены, т.к. оценка все равно перезапишется.
       // Достаточно лишь проверить не произошло ли с этим ходом завершение игры.
       // Правда таких узлов все-равно немного, так что выгода от такой оптимизации будет не больше 5-10%
       EstimatePosition(newNode,false);
       with data[newNode] do begin
        if abs(rate)>200 then begin // недопустимый ход?
         DeleteNode(newNode,true);
         continue;
        end;
        inc(cnt);
        // скорректируем вес
        if flags and movCheck>0 then weight:=weight+10 // безусловное продолжение - нужно проверить можно ли уйти из под шаха
        else
        if flags and movBeat>0 then weight:=weight+6;

        if weight<=0 then continue; // позиция не заслуживает продолжения
       end;
       toAdd[toAddCnt]:=newNode;
       inc(toAddCnt);
      end;
    end;
   if toAddCnt>0 then
    active.Add(@toAdd,toAddCnt)
   else
    if cnt=0 then
     with data[node] do begin
      // Нет ни одного хода: значит либо мат либо пат
      if flags and movCheck=0 then begin
       rate:=0;
       flags:=flags or movStalemate;
      end else begin
       // Если был поставлен шах - то оцениваем позицию как мат
       if whiteTurn xor playerWhite then rate:=-300+depth
        else rate:=300-depth;
       flags:=flags or movCheckmate;
      end;
     end;
  end;

 // Раз в секунду обновляет отображаемый статус AI
 procedure UpdateStats;
  var
   i,est:integer;
   time:int64;
  begin
   // Статистика
   time:=MyTickCount;
   i:=round((time-startTime)/1000);
   if i<>secondsElapsed then begin
    secondsElapsed:=i;
    est:=estCounter-startEstCounter;
    aiStatus:=Format('[%d] Прошло: %d c, позиций: %s, активно %s, оценок: %s, кэш: %.1f%%',
     [stage,secondsElapsed,FormatInt(memSize-freeCnt),
       FormatInt(active.count),FormatInt(est),100*cacheHit/(est+1)]);

    // Кол-во оценок в секунду:
    if lastStatTime>0 then begin
     i:=1000*(estCounter-lastEstCounter) div (time-lastStatTime);
     if i>0 then LogMessage('Rate: %d positions/sec',[i]);
    end;
    lastEstCounter:=estCounter;
    lastStatTime:=time;
   end;
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

 function BaseWeight:integer;
  begin
   // базовый начальный вес
   case aiLevel of
    1:result:=28;
    2:result:=32;
    3:result:=34;
    4:result:=38;
    else
     raise EWarning.Create('Bad AI level');
   end;
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
   stage:=1;
   cacheMiss:=0; cacheHit:=0;
   startTime:=time;
   secondsElapsed:=-1;
   startEstCounter:=estCounter;
   DetectGamePhase;

   // удалить любых потомков curBoard (если есть)
   DeleteChildrenExcept(curBoardIdx,0);

   active.Clear;
   curBoard.weight:=BaseWeight;
   active.Add(curBoardIdx);

   time:=MyTickCount-time;
   LogMessage('StartThinking time = %d',[time]);
  end;


 // Подрезка дерева: удаляются незначимые ветки
 function CutTree(node,recursion:integer):integer;
  const
   CutThreshold:array[0..4] of single=(0,1000,2000,3000,5000);
  var
   n,count,next,deleted,was:integer;
   min,max,v,tr:single;
   st:string;
  begin
   n:=data[node].firstChild;
   if n<=0 then exit;
   was:=freeCnt;
   // Вычисляем минимум и максимум
   count:=1;
   min:=data[n].rate;
   max:=min;
   n:=data[n].nextSibling;
   while n>0 do begin
    inc(count);
    v:=data[n].rate;
    if v<min then min:=v;
    if v>max then max:=v;
    n:=data[n].nextSibling;
   end;

   deleted:=0;
   // А теперь рабочий проход
   n:=data[node].firstChild;
   if count<2 then n:=-1; // единственная ветка нечего удалять
   if (count<4) and // на ходу соперника оставлять минимум 3 варианта (однако их можно подрезать рекурсивно)
      (not data[node].whiteTurn xor playerWhite) then begin
     min:=-10000; max:=10000; // никто не попадёт под это условие
    end;

   while n>0 do begin
    v:=data[n].rate;
    next:=data[n].nextSibling;
    if data[node].whiteTurn xor playerWhite then begin
     // ход AI:
     if (v=min) then begin
       st:=st+data[n].LastTurnAsString+'; ';
       DeleteNode(n);
       inc(deleted);
     end else
      if data[n].quality>CutThreshold[aiLevel] then
       CutTree(n,recursion+1);
    end else begin
     // ход игрока: ветки с низкой оценкой - развиваем, с высокой - удаляем
     if v=max then begin
       st:=st+data[n].LastTurnAsString+'; ';
       DeleteNode(n);
       inc(deleted);
     end else
      if data[n].quality>CutThreshold[aiLevel] then
       CutTree(n,recursion+1);
    end;
    n:=next;
   end;
   if recursion=0 then begin
    n:=memSize-freeCnt;
    result:=freeCnt-was;
    LogMessage('Tree cut: nodes=%d (%d%%), del=%d, ch=%d, min=%.3f, max=%.3f :: %s',
      [n,round(100*n/memSize),result,count-deleted,min,max,st]);
   end;
  end;

 // Вычисляет приоритет развития позиции исходя из текущей оценки и её качества
 function NodePriority(n:integer):single; inline;
  begin
   with data[n] do begin
    if abs(rate)<200 then begin
     if whiteTurn xor playerWhite then
      result:=20-10*rate-sqrt(quality)*0.05 // ход игрока: развивать оценки с низкой оценкой
     else
      result:=20+10*rate-sqrt(quality)*0.05; // ход AI: развивать оценки с высокой оценкой
    end else
     result:=-100;
   end;
  end;

 // Продлить перспективные ветви дерева
 // Нужно чтобы каждая новая фаза не продолжалась слишком уж долго,
 // поэтому по мере углубления дерева нужно уменьшать задачу
 procedure ExtendTree(node,recursion:integer;var outList:PInteger);
  var
   n,count,next,v,boost:integer;
   p,q,max3,max2,max,tr:single;
   prior:array[0..199] of single;
  begin
   n:=data[node].firstChild;
   if n<=0 then exit;
   // Вычисляем рейтинг веток
   count:=0; max:=-100000; max2:=-100000; max3:=-1000000;
   while n>0 do begin
    p:=NodePriority(n);
    prior[count]:=p;
    if p>max then begin max3:=max2; max2:=max; max:=p; end
    else
     if p>max2 then begin max3:=max2; max2:=p; end
      else
       if p>max3 then max3:=p;
    n:=data[n].nextSibling;
    inc(count);
   end;

   // теперь рабочий проход
   n:=data[node].firstChild;
   while n>0 do begin
    p:=NodePriority(n);
    if p>=max2 then begin
     if data[n].quality<1000 then begin
      AddWeight(n,10);
      outList^:=n;
      inc(outList);
     end else
      ExtendTree(n,recursion+1,outList);
    end else // безусловно развить все ветки 1-го уровня, если они совсем слабо развиты
     if (recursion=0) and
        (data[n].quality<30) then begin
      AddWeight(n,10);
      outList^:=n;
      inc(outList);
     end;

    n:=data[n].nextSibling;
   end;

  end;

 // Проверяет достаточно ли собрано информации чтобы сделать ход
 // Возвращает true если ход сделан
 function TryMakeDecision:boolean;
  const
   subQual:array[1..4] of single=(200,300,500,1000);
   qual:array[1..4] of single=(12000,28000,50000,100000);
  var
   q,max:single;
   st:string;
   i,n,best:integer;
   fl:boolean;
  begin
   ASSERT(IsMyTurn);
   ASSERT(curBoard.firstChild>0);
   result:=false;
   n:=memSize-freeCnt;
   LogMessage('--- q=%d nodes=%d (%d%%), estCnt=%d, reqQ=%d, reqSubQ=%d, ',
    [round(curBoard.quality),n,round(100*n/memSize),estCounter,
     round(qual[aiLevel]),round(subQual[aiLevel])]);

   // 1. Имеется ли единственный ход
   n:=curBoard.firstChild;
   if data[n].nextSibling<=0 then begin // единственный ход
    LogMessage('Single turn - no choice');
    moveReady:=n;
    result:=true;
   end;

   // пройдём по всем вариантам и выберем наилучший
   n:=curBoard.firstChild;
   max:=-10000;
   while n>0 do begin
    if data[n].rate>max then begin
     best:=n;
     max:=data[n].rate;
    end;
    n:=data[n].nextSibling;
   end;
   // Победа?
   if max>=200 then begin
    moveReady:=best;
    result:=true;
   end;

   // Единственный ход с высокой оценкой?
   if not result and
      (data[best].quality>subQual[aiLevel]) then begin
    n:=curBoard.firstChild;
    fl:=true;
    while n>0 do begin
     if data[n].rate>max-10 then
      fl:=false;
     n:=data[n].nextSibling;
    end;
    if fl then begin
     LogMessage('Single turn with high score');
     moveReady:=best;
     result:=true;
    end;
   end;

   // 3. Прочие лимиты
   if not result and
     (data[best].quality>subQual[aiLevel]) and
     (curBoard.quality>Qual[aiLevel]) or (MyTickCount-startTime>turnTimeLimit*1000) then begin
    moveReady:=best;
    result:=true;
   end;

   // Если ход выбран...
   if result then begin
    i:=1;
    st:='Tree state:';
    n:=curBoard.firstChild;
    while n>0 do begin
     // вывод всех вариантов в лог
     st:=st+Format(#13#10' %d) %s %.3f (q=%d)',[i,data[n].LastTurnAsString,data[n].rate,round(data[n].quality)]);
     n:=data[n].nextSibling;
     inc(i);
    end;
    LogMessage(st);
    LogMessage(#13#10' -----===== AI turn: %s =====----- ',[data[moveReady].LastTurnAsString]);
    LogMessage('Time: %.1f, est=%d, q=%d',
     [(MyTickCount-startTime)/1000,estCounter-startEstCounter,round(data[moveReady].quality)]);

    startTime:=MyTickCount;
    startEstCounter:=estCounter;
    cacheMiss:=0; cacheHit:=0;
    stage:=0;
    // удаление ненужных веток
    n:=freeCnt;
    DeleteChildrenExcept(curBoardIdx,moveReady);
    LogMessage('Branches deleted, %d nodes removed (%d nodes left)',
     [freeCnt-n,memSize-freeCnt]);

    st:=''; i:=1;
    n:=data[moveReady].firstChild;
    while n>0 do begin
     // вывод всех вариантов в лог
     st:=st+Format(#13#10' %d) %s %.3f (q=%d)',[i,data[n].LastTurnAsString,data[n].rate,round(data[n].quality)]);
     n:=data[n].nextSibling;
     inc(i);
    end;
    LogMessage('New tree state (depth=%d, id=%d): %s',[data[n].depth,n,st]);
    exit;
   end;
  end;

 function BuildNodeName(node:integer):string;
  begin
   result:=data[node].LastTurnAsString+'('+FloatToStrF(data[node].rate,ffFixed,2,2)+')';
   while data[node].parent<>curBoardIdx do begin
    node:=data[node].parent;
    result:=data[node].LastTurnAsString+'->'+result;
   end;
  end;

 procedure UpdateJob;
  var
   time:int64;
   i,n,count:integer;
   pList,p:PInteger;
   list:array[0..1023] of integer;
   st:string;
   min,max:single;
  begin
   time:=MyTickCount;
   try
    // Возможные состояния:
    // 1) нет активных элементов (работа выполнена)
    // 2) закончилась память
    RateTree; // без этого - никуда

    if freeCnt<200 then begin // если мало памяти - обрезать дерево
      active.Clear; // под обрезку могут попасть активные ноды, поэтому быстрее и проще удалить их все а затем добавить заново
      CutTree(curBoardIdx,0);
      if IsMyTurn then  // После обрезки пробуем сделать ход не дожидаясь завершения фазы: раз память заполнена, возможно данных достаточно
       if TryMakeDecision then exit;
      AddWeight(curBoardIdx,0); // таким образом восстанавливается списко активных нодов
      LogMessage('Active after cut: %d',[active.count]);
    end;

    if active.count=0 then begin
      if not isMyTurn or not TryMakeDecision then begin
        active.Clear;
        //VerifyTree;
        if (stage<25) and (stage<stopAfterStage) then begin
         inc(stage);
         if stage=1 then LogMessage('Start thinking: stage 1. CurNode children %d',[CountNodes(curBoardIdx)]);
         pList:=@list;
         ExtendTree(curBoardIdx,0,pList);
         ASSERT(UIntPtr(pList)<UIntPtr(@list[1023]),'Buffer overflow');
         p:=@list;
         while UIntPtr(p)<UIntPtr(pList) do begin
          st:=st+BuildNodeName(p^)+'; ';
          inc(p);
          if p=@list[63] then break;
         end;
         curBoard.MinMaxRate(min,max);

         n:=memSize-freeCnt;
         LogMessage('Stage %d. Nodes: %d (%d%%), extend: %d, min=%.3f, max=%.3f, est=%d'#13#10' Promoted: %s',
          [stage,n,round(100*n/memSize),active.count,min,max,estCounter-startEstCounter,st]);
         if active.count>60000 then begin
          Sleep(0); /// TODO: плохо когда фазы длятся дольше 2-3 секунд
         end;

         time:=MyTickCount-time;
         if time>50 then LogMessage('UpdateJob time %d ms',[time]);
        end else
         if (stage=stopAfterStage) and not (pausedAfterStage) then begin
          pausedAfterStage:=true;
          LogMessage('Paused after stage %d',[stage]);
          ASSERT(active.count=0);
         end;
       end;
     end;
   except
    on e:Exception do ErrorMessage('UpdateJob: '+ExceptionMsg(e));
   end;
  end;

 // Таймер вызывается из главного потока.
 procedure AiTimer;
  begin
   if not started then exit;
   UpdateStats;
  end;

 // Игрок сделал ход: значит curBoard уже указывает на одного из потомков дерева поиска
 // Нужно удалить из дерева лишние ветки, обновить веса и продолжить поиск в текущей ветке
 procedure PlayerMadeTurn;
  var
   cnt,x,y,i,n,k,cellFrom,color,newNode:integer;
   moves:TMovesList;
   st:string;
  begin
   if not started then exit;
   ASSERT(running=false);
   LogMessage('PlayerMadeTurn %s, depth=%d',[curBoard.LastTurnAsString,curBoard.depth]);
   // удаление ненужных веток
   cnt:=freeCnt;
   DeleteChildrenExcept(curBoard.parent,curBoardIdx);
   cnt:=FreeCnt-cnt;
   LogMessage('Deleting branches: %d nodes freed',[cnt]);
   active.Clear;
   stage:=0;
   // Нужно убедиться, что в дереве есть все возможные ходы, т.к. какие-то ветки могли быть удалены при обрезке дерева
   if curBoard.whiteTurn then color:=White else color:=Black;
   for x:=0 to 7 do
    for y:=0 to 7 do begin
      if curBoard.GetPieceColor(x,y)<>color then continue;
      cellFrom:=x+y shl 4;
      GetAvailMoves(curBoard^,cellFrom,moves);
      for k:=1 to moves[0] do begin
       if curBoard.HasChild(cellFrom,moves[k])>0 then continue; // уже есть такой ход
       newNode:=AddChild(curBoardIdx);
       ASSERT(newNode>0);
       DoMove(data[newNode],cellFrom,moves[k]);
       EstimatePosition(newNode,false);
       with data[newNode] do begin
        if abs(rate)>200 then begin // недопустимый ход?
         DeleteNode(newNode,true);
         continue;
        end;
       end;
       data[newNode].weight:=BaseWeight-10;
       active.Add(newNode);
       st:=st+data[newNode].LastTurnAsString+'; ';
      end;
    end;
   if st<>'' then LogMessage('Missing nodes added: '+st);

   LogMessage('Time: %.1f, est=%d',[(MyTickCount-startTime)/1000,estCounter-startEstCounter]);
   st:=''; i:=1;
   n:=curBoard.firstChild;
   while n>0 do begin
    st:=st+Format(#13#10' %d) %s %.3f (q=%d)',[i,data[n].LastTurnAsString,data[n].rate,round(data[n].quality)]);
    inc(i);
    n:=data[n].nextSibling;
   end;
   LogMessage('Tree state after turn: '+st);
   startTime:=MyTickCount;
   cacheMiss:=0; cacheHit:=0;
   startEstCounter:=estCounter;
   ResumeAI;
  end;

 // Инициализация AI
 procedure StartAI;
  var
   i,n:integer;
   sysInfo:TSystemInfo;
  begin
   if started then exit;
   moveReady:=0;
   active.Init;

   // Создать потоки
   GetSystemInfo(sysInfo);
   n:=sysInfo.dwNumberOfProcessors;
   if n>=4 then dec(n);
   if n>=6 then dec(n);
   {$IFDEF SINGLETHREADED}
   n:=1;
   {$ENDIF}
   if not aiMultiThreadedMode then n:=1;
   SetLength(threads,n);
   for i:=0 to high(threads) do
    threads[i]:=TThinkThread.Create(i);

   LogMessage('AI started with %d threads',[n]);

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
   //LogMessage('resumed');
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
   //LogMessage('paused');
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

 { TThinkThread }

 constructor TThinkThread.Create(id: integer);
  begin
   self.id:=id;
   inherited Create;
  end;

 // Поток занимается развитием дерева поиска:
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
   AtomicIncrement(workingThreads);
   try
   repeat
    if not running then begin // no work to do
     idle:=true;
     AtomicDecrement(workingThreads);
     Sleep(5);
     AtomicIncrement(workingThreads);
     continue;
    end;
    idle:=false;

    // поток с ID=0 - управляющий: если все остальные потоки спят
    if (id=0) and (workingThreads=1) and (moveReady=0) and
       ((active.count=0) or (freeCnt<=100)) then begin
      // нет больше активных элементов либо закончилась память
      globalLock.Enter;
      try
       idle:=true;
       PauseAI;
       idle:=false;
       UpdateJob;
       if not pausedAfterStage then ResumeAI;
      finally
       globalLock.Leave;
      end;
      if stage>=10 then Sleep(10);
      if freeCnt<=100 then begin
       LogMessage('Nothing to cut -> sleep');
       Sleep(500);
      end;
      continue;
     end;

    node:=0;
    if freeCnt>100 then // если память на исходе - работать нельзя
     node:=active.Get;
    if node=0 then begin // список пуст - работы нет
     inc(waitCounter);
     AtomicDecrement(workingThreads);
     Sleep(1);
     AtomicIncrement(workingThreads);
     continue;
    end;
    ExtendNode(node);
    inc(counter);

   until terminated;
   AtomicDecrement(workingThreads);
   except
    on e:Exception do ErrorMessage('Error: '+ExceptionMsg(e));
   end;
   threadRunning:=false;
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
  weight:integer;
 begin
  weight:=data[idx].weight;
  if weight>127 then weight:=127;
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
   ASSERT(result>0);
   dec(count);
   if first=last then begin
    first:=0; last:=0;
    // корзина пуста - перейти к следующей
    repeat
     dec(lastBasket);
    until (lastBasket=0) or (baskets[lastBasket].first>0);
   end else begin
    first:=links[result];
   end;
  end;
  Unlock(lock);
 end;

 procedure AiPerfTest;
  var
   i:integer;
   t1:single;
   h:int64;
  begin
{   StartMeasure(1);
   for i:=1 to 3000000 do
    h:=BoardHash(curBoard^);
   t1:=EndMeasure(1);
   ShowMessage(Format('BoardHash time = %3.2f, value=%s',[t1,IntToHex(h)]),'Performance');}

   StartMeasure(1);
   for i:=1 to 300000 do
    EstimatePosition(curBoardIdx,false,true);
   t1:=EndMeasure(1);
   ShowMessage(Format('EstimatePosition = %3.2f',[t1]),'Performance');
  end;

end.
