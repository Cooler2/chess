{$IFDEF CPU386}
{$SETPEFLAGS $20} // Allow 3GB memory space for 32-bit process
{$ENDIF}
// Главное окно игры, интерфейс
{$R+}
unit main;
interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, ExtCtrls, ImgList, StdCtrls, Buttons, Menus,
  System.ImageList;

const
 moveFileName='..\chessmove.txt';
 CELL_SIZE = 64; // размер клетки поля

type
  TMainForm = class(TForm)
    Panel1: TPanel;
    Status: TStatusBar;
    Pieces: TImageList;
    PBox: TImage;
    SwapBtn: TSpeedButton;
    Memo: TMemo;
    ResetBtn: TSpeedButton;
    UndoBtn: TSpeedButton;
    turnWhiteBtn: TSpeedButton;
    TurnBlackBtn: TSpeedButton;
    MenuBtn: TSpeedButton;
    menu1: TPopupMenu;
    MenuSaveTurn: TMenuItem;
    MenuSaveTurn2: TMenuItem;
    MenuSaveTurn3: TMenuItem;
    MenuDeleteTurn: TMenuItem;
    Timer: TTimer;
    ShowTreeBtn: TSpeedButton;
    StartBtn: TSpeedButton;
    ClearBtn: TSpeedButton;
    MenuSaveAllTurns: TMenuItem;
    N4: TMenuItem;
    MenuSaveGame: TMenuItem;
    MenuLoadGame: TMenuItem;
    selLevel: TComboBox;
    Label1: TLabel;
    RedoBtn: TSpeedButton;
    OpenD: TOpenDialog;
    SaveD: TSaveDialog;
    LibEnableBtn: TCheckBox;
    useDbBtn: TCheckBox;
    selfLearnBtn: TCheckBox;
    N1: TMenuItem;
    MenuSaveState: TMenuItem;
    MenuLoadState: TMenuItem;
    multithreadedModeBtn: TCheckBox;
    CacheEnableBtn: TCheckBox;
    procedure DrawBoard(Sender: TObject);
    procedure PBoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SwapBtnClick(Sender: TObject);
    procedure StartBtnClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ResetBtnClick(Sender: TObject);

    procedure AddLastTurnNote;
    procedure NowTurnGroupClick(Sender: TObject);
    procedure UndoBtnClick(Sender: TObject);
    procedure LibBtnMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure MenuSaveTurnClick(Sender: TObject);
    procedure MenuSaveTurn2Click(Sender: TObject);
    procedure MenuSaveTurn3Click(Sender: TObject);
    procedure MenuDeleteTurnClick(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
    procedure Estimate(showExtraStatus:boolean=false);
    procedure ShowTreeBtnClick(Sender: TObject);
    procedure ClearBtnClick(Sender: TObject);
    procedure MenuSaveAllTurnsClick(Sender: TObject);
    procedure MenuSaveGameClick(Sender: TObject);
    procedure MenuLoadGameClick(Sender: TObject);
    procedure selLevelChange(Sender: TObject);
    procedure limitboxChange(Sender: TObject);
    procedure UpdateOptions(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCreate(Sender: TObject);
    procedure MenuSaveStateClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    selected:array[0..7,0..7] of byte; // 1 - клетка с выделенной фигурой, 2 - доступная для хода
    animation:integer; // фаза анимации движения фигуры
    displayBoard:integer; // индекс отображаемой позиции (может отличаться от текущей в режиме просмотра дерева)
    curPiecePos:byte;     // позиция выбранной фигуры
    myTurnStored:boolean;
    procedure ClearSelected;
    procedure MakeAiTurn;
    procedure MakeExternalTurn;
    procedure onTurnMade; // вызывать после изменения curBoardIdx
    procedure UpdateCurPlrBtn;
  end;

var
  MainForm: TMainForm;

implementation
 uses Apus.MyServis,gamedata,logic,AI,TreeView,cache,SelfLearn;
{$R *.dfm}
 var
  turnFrom,turnTo:integer;
  BlackFieldColor,WhiteFieldColor:cardinal;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 if IsAiStarted then StopAI;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
 UseLogFile('chess.log');
 curPiecePos:=255;
 animation:=0;
 InitNewGame;
 displayBoard:=curBoardIdx;
 DrawBoard(sender);
 LoadLibrary;
 LoadRates;
 try
  DeleteFile(moveFileName);
 except
 end;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
 procedure MyStopAI;
  begin
   if startBtn.Down then begin
    startBtn.down:=false;
    startBtn.Click;
   end;
  end;
begin
 if key=VK_F2 then begin
  MyStopAI;
  MenuSaveGame.Click;
 end;
 if key=VK_F3 then begin
  MyStopAI;
  MenuLoadGame.Click;
 end;
 // Тест производительности (на базе текущей позиции)
 if (key=VK_F4) and not startBtn.Down then begin
  Status.Panels[1].Text:='Тест производительности...';
  application.ProcessMessages;
  AiPerfTest;
  Status.Panels[1].Text:='';
 end;
 // F5 - останов и проверка целостности структур данных
 if (key=VK_F5) and IsAiStarted then begin
  if IsAIRunning then begin
   LogMessage('F5: Pausing AI');
   globalLock.Enter;
   try
    PauseAI;
    Status.Panels[1].Text:='AI paused. Verifying tree...';
    Application.ProcessMessages;
    VerifyTree;
    Status.Panels[1].Text:='Paused. Verified.';
    LogMessage('AI Paused');
   finally
    globalLock.Leave;
   end;
  end else begin
   LogMessage('F5: Resuming AI');
   Status.Panels[1].Text:='AI resume';
   globalLock.Enter;
   try
    VerifyTree;
    ResumeAI;
   finally
    globalLock.Leave;
   end;
  end;
 end;

 // F8 - сохранить ход в библиотеке и вернуться к исходной позиции
 if key=VK_F8 then begin
  MenuSaveTurn.Click;
  Status.Panels[1].Text:='Ход сохранён';
  UndoBtn.Click;
 end;
end;

procedure TMainForm.LibBtnMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
 p:TPoint;
begin
 p:=MenuBtn.ClientToScreen(point(x,y));
 menu1.Popup(p.x,p.y);
end;

procedure TMainForm.limitboxChange(Sender: TObject);
begin
 /// TODO
{ if StartBtn.Down then thread.plimit:=limitbox.Itemindex;
 UpdateSelfLearn;}
end;

procedure TMainForm.MenuSaveTurn3Click(Sender: TObject);
begin
 AddlastMoveToLibrary(4);
end;
procedure TMainForm.MenuSaveTurn2Click(Sender: TObject);
begin
 AddlastMoveToLibrary(6);
end;
procedure TMainForm.MenuSaveTurnClick(Sender: TObject);
begin
 AddlastMoveToLibrary(10);
end;

procedure TMainForm.MakeAiTurn;
var
 f:TextFile;
begin
  curBoardIdx:=moveReady;
  curBoard:=@data[curBoardIdx];
  LogMessage('Get turn from AI: %s',[curBoard.LastTurnAsString]);
  moveReady:=0;

  try // записать ход в файл
   AssignFile(f,moveFileName);
   rewrite(f);
   writeln(f,curBoard.lastTurnFrom,' ',curBoard.lastTurnTo);
   closeFile(f);
   myTurnStored:=true;
  except
  end;
  onTurnMade;
end;

procedure TMainForm.MakeExternalTurn;
var
 f:TextFile;
 x,y,i:integer;
begin
 try
  assignFile(f,moveFileName);
  reset(f);
  readln(f,TurnFrom,TurnTo);
  closeFile(f);
  LogMessage(' === External turn: %s %s ===',[NameCell(turnFrom),nameCell(turnTo)]);
  DeleteFile(moveFileName);
  if PlayerWhite then begin
   x:=40+CELL_SIZE*(TurnFrom and $F);
   y:=40+CELL_SIZE*(7-TurnFrom shr 4);
  end else begin
   x:=40+CELL_SIZE*(7-TurnFrom and $F);
   y:=40+CELL_SIZE*(TurnFrom shr 4);
  end;
  PBoxMouseDown(mainForm,mbLeft,[],x,y);
  for i:=1 to 10 do begin
   application.ProcessMessages;
   Sleep(20);
  end;
  if PlayerWhite then begin
   x:=40+CELL_SIZE*(TurnTo and $F);
   y:=40+CELL_SIZE*(7-TurnTo shr 4);
  end else begin
   x:=40+CELL_SIZE*(7-TurnTo and $F);
   y:=40+CELL_SIZE*(TurnTo shr 4);
  end;
  PBoxMouseDown(MainForm,mbLeft,[],x,y);
 except
 end;
end;

procedure TMainForm.MenuDeleteTurnClick(Sender: TObject);
begin
 DeleteLastMoveFromLibrary;
end;

procedure TMainForm.MenuSaveAllTurnsClick(Sender: TObject);
var
 i:integer;
begin
 AddAllMovesToLibrary(10);
end;

procedure TMainForm.MenuSaveGameClick(Sender: TObject);
var
 f:TextFile;
 i:integer;
 b:integer;
begin
 if not SaveD.Execute then exit;
 AssignFile(f,SaveD.FileName);
 Rewrite(f);
 b:=curBoardIdx;
 while b>=0 do begin
  writeln(f,data[b].ToString);
  b:=data[b].parent;
 end;
 CloseFile(f);
end;

procedure TMainForm.MenuLoadGameClick(Sender: TObject);
var
 f:TextFile;
 i:integer;
 st:string;
 sa:StringArr;
begin
 OpenD.InitialDir:=GetCurrentDir;
 if not OpenD.Execute then exit;
 if not fileExists(openD.Filename) then exit;
 AssignFile(f,OpenD.filename);
 Reset(f);
 InitNewGame;
 while not eof(f) do begin
  readln(f,st);
  if st<>'' then AddString(sa,st);
 end;
 CloseFile(f);
 if length(sa)>0 then begin
  i:=high(sa);
  curBoard.FromString(sa[i]);
  memo.Lines.Clear;
  while i>0 do begin
   dec(i);
   curBoardIdx:=AddChild(curBoardIdx);
   curBoard:=@data[curBoardIdx];
   curBoard.FromString(sa[i]);
   AddLastTurnNote;
  end;
 end;
 displayBoard:=curBoardIdx;
 undoBtn.enabled:=curBoard.parent>=0;
 redobtn.enabled:=false;
 UpdateCurPlrBtn;

 ClearCache;
 DrawBoard(sender);
end;

procedure TMainForm.MenuSaveStateClick(Sender: TObject);
begin
 PauseAI;
end;

procedure TMainForm.NowTurnGroupClick(Sender: TObject);
begin
 if StartBtn.Down then begin
  UpdateCurPlrBtn;
  exit;
 end;
 if curBoard.parent>=0 then
  if not AskYesNo('История партии будет удалена.'#13#10'Вы уверены?','Внимание!') then begin
   UpdateCurPlrBtn;
   exit;
  end;
 curBoard.whiteTurn:=turnWhiteBtn.Down;
 memo.Lines.Clear;
 onTurnMade;
end;

// Один из игроков сделал ход
procedure TMainForm.onTurnMade;
begin
  displayBoard:=curBoardIdx;
  ClearSelected;
  AddLastTurnNote;
  redoBtn.enabled:=false; // последний ход - вперёд двигаться некуда
  undoBtn.enabled:=not startBtn.Down; // нельзя отменять ход во время работы AI
  curPiecePos:=255;
  if curBoard.parent>=0 then animation:=1; // начинаем анимацию хода
  DrawBoard(mainForm);
  Estimate;
  if gameState=0 then
   if curBoard.whiteTurn then turnWhiteBtn.Down:=true
    else turnBlackBtn.Down:=true;
  // игра окончена?
  if gameState in [1..3] then StopAI
  else
   if startBtn.Down and
    (curBoard.whiteTurn<>playerWhite) then PlayerMadeTurn;
end;

procedure TMainForm.PBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
 i,j,v,cx,cy,piece,cell:integer;
 color,color2:byte;
 b:TBoard;
 moves:TMovesList;
 beatable:TBeatable;
begin
 try
 if treeWnd.Visible then exit;
 if animation>0 then exit;
 i:=(x-15) div CELL_SIZE;
 j:=(y-15) div CELL_SIZE;
 if playerWhite then j:=7-j else i:=7-i;
 if not ((i in [0..7]) and (j in [0..7])) then exit; // клик вне поля

 if curBoard.whiteTurn then begin
   color:=white; color2:=black;
 end else begin
   color:=black; color2:=white;
 end;

 // Редактирование доски: Alt+click - белые Ctrl+Alt+click - черные
 if (startBtn.Down=false) and (button=mbLeft) and (ssAlt in shift) then
  with curBoard^ do begin
   piece:=GetCell(i,j);
   if ssCtrl in shift then
    case piece of
     0:piece:=PawnBlack;
     PawnBlack:piece:=RookBlack;
     RookBlack:piece:=KnightBlack;
     KnightBlack:piece:=BishopBlack;
     BishopBlack:piece:=QueenBlack;
     QueenBlack:piece:=KingBlack;
     KingBlack:piece:=0;
    end
   else
    case piece of
     0:piece:=PawnWhite;
     PawnWhite:piece:=RookWhite;
     RookWhite:piece:=KnightWhite;
     KnightWhite:piece:=BishopWhite;
     BishopWhite:piece:=QueenWhite;
     QueenWhite:piece:=KingWhite;
     KingWhite:piece:=0;
    end;
   SetCell(i,j,piece);
   DrawBoard(sender);
   exit;
  end;

 // Очистка клетки
 if (startBtn.Down=false) and (button=mbRight) and (ssAlt in shift) then begin
   curBoard.SetCell(i,j,0);
   DrawBoard(sender);
   exit;
 end;

 if (button=mbLeft) then begin
   // если не наш ход и компьютер думает - двигать нельзя
   if StartBtn.Down and (playerWhite xor curBoard.WhiteTurn) then exit;
   cell:=i+j shl 4;
   // если выбранная клетка содержит фигуру нашего цвета - выберем её
   if (curBoard.CellOccupied(i,j) and (curBoard.GetPieceColor(i,j)=color)) then begin
    // выбор фигуры для хода
    ClearSelected;
    v:=curBoard.GetCell(i,j);
    if v and ColorMask<>color then exit;
    selected[i,j]:=selected[i,j] xor 1;
    curPiecePos:=cell;
    GetAvailMoves(curBoard^,curPiecePos,moves);
    for i:=1 to moves[0] do
     selected[moves[i] and $F,moves[i] shr 4]:=2;
    DrawBoard(sender);
   end else begin
    if curPiecePos=cell then begin
     // клик в то же поле = отмена выбора
     curPiecePos:=255;
     ClearSelected;
    end else begin
     // выбрано целевое поле
     if selected[i,j]=2 then begin // можно пойти
      // проверить допустимость хода
      b:=curBoard^;
      DoMove(b,curPiecePos,cell);
      CalcBeatable(b,beatable);
      for cx:=0 to 7 do
       for cy:=0 to 7 do
        if (b.GetCell(cx,cy)=King+color) and (beatable[cx,cy] and color2>0) then begin
         ShowMessage('Недопустимый ход! '+inttostr(cx)+' '+inttostr(cy),'');
         ClearSelected;
         DrawBoard(sender);
         exit;
        end;
      // Ход можно делать
      globalLock.Enter;
      try
       PauseAI;
       // нет ли уже в дереве соответствующего продолжения
       i:=curBoard.HasChild(curPiecePos,cell);
       if i>0 then begin
        curBoardIdx:=i;
        curBoard:=@data[curBoardIdx];
       end else begin
        // если нет - создать его
        curBoardIdx:=AddChild(curBoardIdx);
        curBoard:=@data[curBoardIdx];
        DoMove(curBoard^,curPiecePos,cell);
       end;
       LogMessage(#13#10'  -----===== Player turn: %s =====-----',[curBoard.LastTurnAsString]);
       onTurnMade;
      finally
       globalLock.Leave;
      end;
     end;
    end;
   end;
 end;

 except
  on e:exception do ForceLogMessage('Click error: '+ExceptionMsg(e));
 end;

 DrawBoard(sender);
end;

procedure TMainForm.ResetBtnClick(Sender: TObject);
begin
 ClearSelected;
 InitNewGame;
 displayBoard:=curBoardIdx;
 memo.Lines.Clear;
 DrawBoard(sender);
end;

procedure TMainForm.UpdateCurPlrBtn;
begin
 turnWhiteBtn.Down:=curBoard.whiteTurn;
 TurnBlackBtn.Down:=not curBoard.whiteTurn;
end;

procedure TMainForm.UpdateOptions(Sender: TObject);
begin
 aiUseLibrary:=LibEnableBtn.checked;
 aiUseDB:=useDbBtn.Checked;
 aiSelfLearn:=selfLearnBtn.Checked;
 aiMultithreadedMode:=multithreadedModeBtn.Checked;
 aiCacheEnabled:=CacheEnableBtn.Checked;
end;

procedure TMainForm.selLevelChange(Sender: TObject);
begin
 aiLevel:=selLevel.Itemindex+1;
 case aiLevel of
  1:turnTimeLimit:=3;
  2:turnTimeLimit:=5;
  3:turnTimeLimit:=10;
  4:turnTimeLimit:=20;
 end;
end;

procedure TMainForm.UndoBtnClick(Sender: TObject);
var
 i:integer;
begin
 if sender=UndoBtn then begin
  if curBoard.parent>0 then begin
   curboardIdx:=curBoard.parent;
   curBoard:=@data[curBoardIdx];
   if curBoard.whiteturn then
    memo.Lines.Delete(memo.lines.Count-1)
   else begin
    i:=memo.lines.count-1;
    memo.lines[i]:=copy(memo.lines[i],1,10);
   end;
  end;
 end;
 if sender=RedoBtn then begin
  if curBoard.firstChild>0 then begin
    curBoardIdx:=curBoard.firstChild;
    curBoard:=@data[curBoardIdx];
    AddLastTurnNote;
   end;
 end;
 UpdateCurPlrBtn;
 UndoBtn.Enabled:=curBoard.parent>0;
 RedoBtn.enabled:=curBoard.firstChild>0;
 displayBoard:=curboardIdx;
 DrawBoard(sender);
end;

procedure TMainForm.ShowTreeBtnClick(Sender: TObject);
begin
 if StartBtn.Down and IsAiRunning then begin
  PauseAfterThisStage(true);
  status.Panels[0].Text:='Waiting...';
  repeat
   application.ProcessMessages;
   Sleep(5);
  until IsPausedAfterStage;
  status.Panels[0].Text:='';
 end;
 TreeWnd.Show;
end;

procedure TMainForm.StartBtnClick(Sender: TObject);
begin
 if StartBtn.down then begin // кнопку нажали
  SelLevelChange(sender); // обновить сложность
  UpdateOptions(sender);
  startBtn.Caption:='Stop AI';
  swapBtn.Enabled:=false;
  resetBtn.enabled:=false;
  clearBtn.enabled:=false;
  undoBtn.enabled:=false;
  redobtn.enabled:=false;
  menuBtn.enabled:=false;
{  turnWhiteBtn.Enabled:=false;
  turnBlackBtn.Enabled:=false;}
  StartAI;
 end else begin
  startBtn.Enabled:=false;
  startBtn.Caption:='Stopping...';
  application.ProcessMessages;
  StopAI;
  startBtn.Enabled:=true;
  startBtn.Caption:='Start AI';
  SwapBtn.Enabled:=true;
  ResetBtn.enabled:=true;
  ClearBtn.enabled:=true;
  MenuBtn.enabled:=true;
  turnWhiteBtn.Enabled:=true;
  turnBlackBtn.Enabled:=true;
  undoBtn.enabled:=curBoard.parent>0;
  redobtn.enabled:=curBoard.firstChild=curBoard.lastChild;
 end;
end;

procedure TMainForm.SwapBtnClick(Sender: TObject);
begin
 PlayerWhite:=not PlayerWhite;
 DrawBoard(sender);
 // Необходима очистка кэша, т.к. оценки справедливы для другого игрока
 ClearCache;
end;

procedure TMainForm.TimerTimer(Sender: TObject);
begin
 try
 // Анимация хода - двигаем фигуру
 if animation>0 then begin
  inc(animation);
  if animation=10 then animation:=0;
  DrawBoard(sender);
 end;

 // попинать AI
 if StartBtn.Down then AiTimer;

 if StartBtn.Down then begin
  if not TreeWnd.Visible then
   status.Panels[1].Text:=AiStatus;
  if (gameState in [1..3]) then begin // остановка AI если игра окончена
   StartBtn.Down:=false;
   StartBtn.Click;
  end;
 end;

 // если за игрока сделан ход - записан во внешнем файле
 if IsPlayerTurn and (animation=0) then begin
    if FileExists(moveFileName) then begin
     if not myTurnStored then MakeExternalTurn;
    end else
     myTurnStored:=false; // файл отсутствует - значит был удалён потребителем, и если появится снова - это для нас
 end;

 if StartBtn.Down and not IsPlayerTurn and (animation=0)
    and (moveReady>0) then MakeAiTurn;
 except
  on e:Exception do ForceLogMessage('Error in Timer: '+ExceptionMsg(e));
 end;
end;

procedure TMainForm.AddLastTurnNote;
var
 i,j:integer;
 v:byte;
 st,s2:string;
 beatable:TBeatable;
begin
 if curBoard.parent<0 then exit;

 st:=curBoard.LastTurnAsString(false);
 CalcBeatable(curBoard^,beatable);
 with curBoard^ do
  for i:=0 to 7 do
   for j:=0 to 7 do
    if (GetCell(i,j)=KingWhite) and (beatable[i,j] and Black>0) or
       (GetCell(i,j)=KingBlack) and (beatable[i,j] and White>0) then st:=st+'+';

  while length(st)<7 do st:=st+' ';
  s2:=''; if memo.lines.count<9 then s2:=' ';
  if curBoard.whiteTurn then
   memo.Lines[memo.Lines.Count-1]:=memo.Lines[memo.Lines.Count-1]+' '+st
  else
   memo.Lines.Add(s2+inttostr(memo.lines.Count+1)+' '+st);
end;

procedure TMainForm.ClearBtnClick(Sender: TObject);
begin
 InitNewGame;
 curBoard.Clear;
 memo.Lines.Clear;
 DrawBoard(sender);
end;

procedure TMainForm.ClearSelected;
begin
 FillChar(selected,sizeof(selected),0);
end;

procedure TMainForm.DrawBoard(Sender: TObject);
var
 i,j,k,v,w:integer;
 c:cardinal;
 x1,y1,x2,y2:integer;
begin
 try
 with PBox.Canvas do begin
  brush.Color:=$B0CADA;
  w:=8*CELL_SIZE+30;
  FillRect(rect(0,0,w,w));
  pen.color:=$202020;
  Rectangle(14,14,w-14,w-14);
  // Доска
  for i:=0 to 7 do
   for j:=0 to 7 do begin
    if (i xor j) mod 2=1 then
     brush.color:=BlackFieldColor
    else
     brush.color:=WhiteFieldColor;
    fillRect(rect(15+i*CELL_SIZE,15+j*CELL_SIZE,15+(i+1)*CELL_SIZE,15+(j+1)*CELL_SIZE));
    c:=0;
    k:=j; v:=i;
    if playerWhite then k:=7-k else v:=7-i;
    // выделенные клетки
    if selected[v,k] and 2>0 then c:=$90C090;
    if selected[v,k] and 1>0 then c:=$D0C090;
    if c>0 then
    for k:=0 to 2 do begin
     pen.color:=c;
     c:=c-$101010;
     Rectangle(15+i*CELL_SIZE+k,15+j*CELL_SIZE+k,15+(i+1)*CELL_SIZE-k,15+(j+1)*CELL_SIZE-k);
    end;
   end;
  // Подписи клеток
  font.Size:=10;
  font.Style:=[fsBold];
  brush.style:=bsClear;
  if playerWhite then
   for i:=1 to 8 do begin
    TextOut(3,w+8-i*CELL_SIZE,inttostr(i));
    TextOut(w-11,w+8-i*CELL_SIZE,inttostr(i));
    TextOut(i*CELL_SIZE-18,-2,chr(96+i));
    TextOut(i*CELL_SIZE-18,w-16,chr(96+i));
   end
  else
   for i:=1 to 8 do begin
    TextOut(3,w+7-i*CELL_SIZE,inttostr(9-i));
    TextOut(w-11,w+7-i*CELL_SIZE,inttostr(9-i));
    TextOut(i*CELL_SIZE-18,-2,chr(96-i+9));
    TextOut(i*CELL_SIZE-18,w-16,chr(96-i+9));
   end;

  // Фигуры
  with data[displayBoard] do
   for i:=0 to 7 do
    for k:=0 to 7 do begin
     j:=k; v:=i;
     if playerWhite then j:=7-j else v:=7-v;
     if CellOccupied(v,k) then begin
      if (animation>0) and (v=lastTurnTo and $F) and (k=lastTurnTo shr 4) then continue;
      Pieces.Draw(PBox.canvas, 15+round((i+0.5)*CELL_SIZE)-30, 15+round((j+0.5)*CELL_SIZE)-30,
        GetPieceType(v,k)-1+6*byte(GetPieceColor(v,k)=Black));
     end;
    end;

  // Анимация хода
  if animation>0 then
   with data[displayBoard] do begin
    v:=lastTurnTo and $F;
    k:=lastTurnTo shr 4;
    x1:=lastTurnFrom and $F;
    y1:=lastTurnFrom shr 4;
    x2:=lastTurnTo and $F;
    y2:=lastTurnTo shr 4;
    if playerWhite then begin
     y1:=7-y1; y2:=7-y2;
    end else begin
     x1:=7-x1; x2:=7-x2;
    end;
    i:=15+round(CELL_SIZE*(0.5+x1+(animation/9)*(x2-x1)))-30;
    j:=15+round(CELL_SIZE*(0.5+y1+(animation/9)*(y2-y1)))-30;
    Pieces.Draw(PBox.canvas,i,j,GetPieceType(v,k)-1+6*byte(GetPieceColor(v,k)=Black));
   end;
 end;
 except
  on e:Exception do ForceLogMessage('Paint error: '+ExceptionMsg(e));
 end;
end;

procedure CheckGameOver;
var
 i,j,cnt,color:integer;
 moves:TMovesList;
begin
 // Есть ли ходы?
 if curBoard.whiteTurn then color:=White else color:=Black;
 cnt:=0;
 for i:=0 to 7 do
  for j:=0 to 7 do
   if curBoard.GetPieceColor(i,j)=color then begin
    GetAvailMoves(curBoard^,i+j shl 4,moves);
    inc(cnt,moves[0]);
   end;
 if cnt=0 then
  if curBoard.flags and movCheck>0 then
   curBoard.SetFlag(movCheckMate)
  else
   curBoard.SetFlag(movStalemate);
end;

// Оценивает позицию и, если надо, завершает игру
procedure TMainForm.Estimate;
var
 r:single;
 fl:boolean;
 v1,v2,i,j:integer;
begin
 if displayBoard<>curBoardIdx then begin
  data[0]:=data[displayBoard]; // чтобы не портить текущую позицию
  i:=0;
 end else
  i:=curBoardIdx;
 EstimatePosition(i,false,true);
 with data[i] do begin
  r:=-rate; // в базе оценка за соперника, показываем противоположную
  status.Panels[0].text:=Format('%5.3f : %5.3f = %4.3f',[whiteRate,blackRate,r]);

  if showExtraStatus then
   status.Panels[1].text:=Format('w=%d flags=%x rF=%x q=%d depth=%d sub=%d',
     [weight,flags,rFlags,round(quality),depth,CountNodes(i)]);
 end;

 if displayBoard<>curBoardIdx then exit;

 CheckGameOver;
 if curBoard.flags and movRepeat>0 then begin
  gameState:=1;
  ShowMessage('Повторение ходов!','Конец игры');
 end;
 if curBoard.flags and movStalemate>0 then begin
  gameState:=1;
  ShowMessage('Пат.','Конец игры');
 end;
 if curBoard.flags and movCheckmate>0 then
  if curBoard.whiteTurn then begin
   gameState:=2;
   ShowMessage('Мат белым!','Конец игры');
  end else begin
   gameState:=3;
   ShowMessage('Мат черным!','Конец игры');
  end;

 // возможно мата нет но и выиграть уже нельзя?
 if gameState=0 then begin
  fl:=false; v1:=0; v2:=0;
  for i:=0 to 7 do
   for j:=0 to 7 do begin
    if curBoard.GetPieceType(i,j)=Pawn then begin
     fl:=true; break;
    end;
    case curBoard.GetCell(i,j) of
     Rookwhite:inc(v1,5);
     BishopWhite:inc(v1,3);
     KnightWhite:inc(v1,3);
     QueenWhite:inc(v1,9);
     RookBlack:inc(v2,5);
     BishopBlack:inc(v2,3);
     KnightBlack:inc(v2,3);
     QueenBlack:inc(v2,9);
    end;
   end;
  if not fl and (v1<5) and (v2<5) then begin
   gameState:=1;
   ShowMessage('Ничья.','Конец игры');
  end;
 end;

end;

initialization
// BlackFieldColor:=StrToInt('$00335C8E');
// WhiteFieldColor:=StrToInt('$008aC5f2');
 BlackFieldColor:=StrToInt('$006580A0');
 WhiteFieldColor:=StrToInt('$00C0E0E8');
end.
