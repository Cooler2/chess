unit main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, ExtCtrls, ImgList, StdCtrls, Buttons, Menus,
  System.ImageList;

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
    N1: TMenuItem;
    N061: TMenuItem;
    N041: TMenuItem;
    N2: TMenuItem;
    Timer: TTimer;
    ShowTreeBtn: TSpeedButton;
    StartBtn: TSpeedButton;
    ClearBtn: TSpeedButton;
    N3: TMenuItem;
    N4: TMenuItem;
    N5: TMenuItem;
    N6: TMenuItem;
    selLevel: TComboBox;
    Label1: TLabel;
    limitbox: TComboBox;
    Label2: TLabel;
    RedoBtn: TSpeedButton;
    OpenD: TOpenDialog;
    SaveD: TSaveDialog;
    LibEnableBtn: TCheckBox;
    selfLearn: TCheckBox;
    procedure DrawBoard(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure PBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
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
    procedure N1Click(Sender: TObject);
    procedure N061Click(Sender: TObject);
    procedure N041Click(Sender: TObject);
    procedure N2Click(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
    procedure Estimate;
    procedure CheckGameover;
    procedure ShowTreeBtnClick(Sender: TObject);
    procedure LibEnableBtnClick(Sender: TObject);
    procedure ClearBtnClick(Sender: TObject);
    procedure N3Click(Sender: TObject);
    procedure N5Click(Sender: TObject);
    procedure N6Click(Sender: TObject);
    procedure selLevelChange(Sender: TObject);
    procedure limitboxChange(Sender: TObject);
    procedure selfLearnClick(Sender: TObject);
  private
    { Private declarations }
    procedure UpdateSelfLearn;
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

  curPiece:byte=255;
  autoChangedTurn:boolean=false;
  selfLearnState:boolean;

implementation
 uses logic,TreeView;
{$R *.dfm}
 var
  turnFrom,turnTo:integer;
  BlackFieldColor,WhiteFieldColor:cardinal;

procedure TMainForm.FormActivate(Sender: TObject);
begin
 InitBoard(board);
 DrawBoard(sender);
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 if thread<>nil then Thread.Terminate;
end;

procedure TMainForm.LibBtnMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
 p:TPoint;
begin
 p:=MenuBtn.ClientToScreen(point(x,y));
 menu1.Popup(p.x,p.y);
end;

procedure TMainForm.LibEnableBtnClick(Sender: TObject);
begin
 if StartBtn.Down then
  thread.useLibrary:=LibEnableBtn.checked;
end;

procedure TMainForm.limitboxChange(Sender: TObject);
begin
 if StartBtn.Down then thread.plimit:=limitbox.Itemindex;
 UpdateSelfLearn;
end;

procedure TMainForm.N041Click(Sender: TObject);
begin
 AddlastMoveToLibrary(4);
end;
procedure TMainForm.N061Click(Sender: TObject);
begin
 AddlastMoveToLibrary(6);
end;
procedure TMainForm.N1Click(Sender: TObject);
begin
 AddlastMoveToLibrary(10);
end;

procedure TMainForm.N2Click(Sender: TObject);
begin
 DeleteLastMoveFromLibrary;
end;

procedure TMainForm.N3Click(Sender: TObject);
var
 i:integer;
begin
 AddAllMovesToLibrary(10);
end;

procedure TMainForm.N5Click(Sender: TObject);
var
 f:file;
 i:integer;
begin
 if not SaveD.Execute then exit;
 assignFile(f,SaveD.FileName);
 rewrite(f,1);
 blockwrite(f,PlayerWhite,1);
 blockwrite(f,GameOver,1);
 blockwrite(f,HistoryPos,4);
 blockwrite(f,HistorySize,4);
 seek(f,128);
 blockwrite(f,board,sizeof(board));
 for i:=1 to HistoryPos do begin
  seek(f,128+i*128);
  blockwrite(f,history[i],sizeof(TBoard));
 end;
 closeFile(f);
end;

procedure TMainForm.N6Click(Sender: TObject);
var
 f:file;
 i,n,m:integer;
begin
 if not OpenD.Execute then exit; 
 if not fileExists(openD.Filename) then exit;
 assignFile(f,OpenD.filename);
 reset(f,1);
 blockread(f,PlayerWhite,1);
 blockread(f,GameOver,1);
 blockread(f,n,4);
 blockread(f,m,4);
 memo.Lines.Clear;
 for i:=1 to n do begin
  seek(f,128+i*128);
  blockread(f,board,sizeof(board));
  AddLastTurnNote;
  history[i]:=board;
 end;
 historyPos:=n;
 historySize:=m;
 seek(f,128);
 blockread(f,board,sizeof(board));
 history[m]:=board;
 AddLastTurnNote;
 undoBtn.enabled:=HistoryPos>0;
 redobtn.enabled:=false;
 closeFile(f);
 DrawBoard(sender);
end;

procedure TMainForm.NowTurnGroupClick(Sender: TObject);
begin
 board.WhiteTurn:=TurnWhiteBtn.Down;
 memo.Lines.Clear;
end;

procedure TMainForm.PBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
 i,j,v,cx,cy:integer;
 color,color2:byte;
 b:TBoard;
begin
 if animation>0 then exit;
 i:=(x-15) div 60;
 j:=(y-15) div 60;
 if PlayerWhite then j:=7-j else i:=7-i;
 if (i in [0..7]) and (j in [0..7]) then begin

  if board.WhiteTurn then begin color:=White; color2:=black; end
   else begin color:=Black; color2:=white; end;
  if (button=mbLeft) then begin
   // если не наш ход и компьютер думает - двигать нельзя
   if StartBtn.Down and (PlayerWhite xor board.WhiteTurn) then exit;
   if (curPiece=255) or (board.field[i,j] and Colormask=color) then begin
    fillchar(selected,sizeof(selected),0);
    v:=board.field[i,j];
    if v and ColorMask<>color then exit;
    selected[i,j]:=selected[i,j] xor 1;
    curPiece:=i+j shl 4;
    GetAvailMoves(board,curPiece);
    for i:=1 to mCount do
     selected[moves[i] and $F,moves[i] shr 4]:=2;
    DrawBoard(sender);
   end else begin
    if curPiece=i+j shl 4 then begin // отмена выбора
     curPiece:=255;
     fillchar(selected,sizeof(selected),0);
    end else begin // Делаем ход
     if selected[i,j]=2 then begin // можно пойти
      // проверить допустимость хода
      b:=board;
      DoMove(b,curPiece,i+j shl 4);
      CalcBeatable(b);
      for cx:=0 to 7 do
       for cy:=0 to 7 do
        if (b.field[cx,cy]=King+color) and (beatable[cx,cy] and color2>0) then begin
         ShowMessage('Недопустимый ход! '+inttostr(cx)+' '+inttostr(cy));
         fillchar(selected,sizeof(selected),0);
         DrawBoard(sender);
         exit;
        end;

      inc(historyPos);
      history[historyPos]:=board;
      historysize:=historypos+1;
      history[historySize]:=b;
      RedoBtn.enabled:=false;
      undoBtn.Enabled:=not StartBtn.Down;
      board:=b;
      AddLastTurnNote;
      fillchar(selected,sizeof(selected),0);
      curPiece:=255;
      animation:=1;
      DrawBoard(sender);
      Estimate;
      CheckGameover;
      if gameover=0 then
       if board.WhiteTurn then turnWhiteBtn.Down:=true
        else turnBlackBtn.Down:=true;
     end;
    end;
   end;
  end;

  if (button=mbRight) and (startBtn.Down=false) then with board do begin
   inc(board.field[i,j]);
   if field[i,j]=1 then field[i,j]:=PawnWhite;
   if board.field[i,j]=$47 then board.field[i,j]:=PawnBlack;
   if board.field[i,j]=$87 then board.field[i,j]:=0;
  end;
  DrawBoard(sender);
 end;
end;

procedure TMainForm.PBoxMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
var
 i,j:integer;
begin
{ for i:=0 to 7 do
  for j:=0 to 7 do
   selected[i,j]:=selected[i,j] and $FE;
 i:=(x-15) div 60;
 j:=(y-15) div 60;
 if PlayerWhite then j:=7-j else i:=7-i;
 if (i in [0..7]) and (j in [0..7]) then
  selected[i,j]:=selected[i,j] or 1;
 DrawBoard(sender);}
end;

procedure TMainForm.ResetBtnClick(Sender: TObject);
begin
 InitBoard(board);
 memo.Lines.Clear;
 DrawBoard(sender);
end;

procedure TMainForm.selfLearnClick(Sender: TObject);
begin
 if StartBtn.Down then thread.selfTeach:=selfLearn.Checked;
end;

procedure TMainForm.selLevelChange(Sender: TObject);
begin
 if StartBtn.Down then thread.level:=selLevel.Itemindex;
 UpdateSelfLearn;
end;

procedure TMainForm.UndoBtnClick(Sender: TObject);
var
 i:integer;
begin
 if sender=UndoBtn then begin
  if historyPos>0 then begin
   board:=history[historyPos];
   dec(historyPos,1);
   if board.whiteturn then
    memo.Lines.Delete(memo.lines.Count-1)
   else begin
    i:=memo.lines.count-1;
    memo.lines[i]:=copy(memo.lines[i],1,10);
   end;
  end;
 end;
 if sender=RedoBtn then begin
  if historyPos<historySize-1 then begin
   board:=history[historyPos+2];
   inc(historyPos,1);
   AddLastTurnNote;
  end;
 end;
 UndoBtn.Enabled:=historyPos>0;
 RedoBtn.enabled:=historyPos<historySize-1;
 DrawBoard(sender);
end;

procedure TMainForm.UpdateSelfLearn;
var
 fl:boolean;
begin
 fl:=(selLevel.ItemIndex>1) and (limitBox.ItemIndex=0);
 if not fl and selfLearn.Enabled then begin
  selfLearnState:=selfLearn.checked;
  selfLearn.Checked:=false;
  selfLearn.Enabled:=false;
 end;
 if fl and not selflearn.Enabled then begin
  selfLearn.Enabled:=true;
  selfLearn.Checked:=selfLearnState;
 end;
end;

procedure TMainForm.ShowTreeBtnClick(Sender: TObject);
begin
 TreeWnd.ShowModal;
end;

procedure TMainForm.StartBtnClick(Sender: TObject);
begin
 if StartBtn.down then begin // кнопку нажали
  thread:=ThinkThread.Create(true);
  thread.Reset;
  thread.useLibrary:=LibEnableBtn.checked;
  thread.selfTeach:=selfLearn.Checked;
  thread.level:=selLevel.ItemIndex;
  thread.plimit:=limitbox.ItemIndex;
  thread.Resume;
  StartBtn.Caption:='Stop AI';
  SwapBtn.Enabled:=false;
  ResetBtn.enabled:=false;
  ClearBtn.enabled:=false;
  undoBtn.enabled:=false;
  redobtn.enabled:=false;
  menuBtn.enabled:=false;
 end else begin
  // кнопку отжали
  thread.Terminate;
  startBtn.Enabled:=false;
  startBtn.Caption:='Stopping...';
 end;
end;

procedure TMainForm.SwapBtnClick(Sender: TObject);
begin
 PlayerWhite:=not PlayerWhite;
 DrawBoard(sender);
 // Необходима очистка кэша, т.к. оценки справедливы для другого игрока 
 fillchar(cache,sizeof(cache),0);
end;

procedure TMainForm.TimerTimer(Sender: TObject);
const
 moveFileName='chessmove.txt';
var
 f:textFile;
 x,y:integer;
begin
 if animation>0 then begin
  inc(animation);
  if animation=10 then animation:=0;
  DrawBoard(sender);
  exit;
 end;
// Estimate;
 if not startBtn.Enabled and not thread.running then begin
  StartBtn.enabled:=true;
  StartBtn.Caption:='Start AI';
  SwapBtn.Enabled:=true;
  ResetBtn.enabled:=true;
  ClearBtn.enabled:=true;
  MenuBtn.enabled:=true;
  UndoBtnClick(sender);
 end;

 if StartBtn.Down then status.Panels[1].Text:=thread.status;
 if StartBtn.Down and (gameover in [1..3]) then begin
  StartBtn.Down:=false;
  StartBtn.Click;
//  ShowMessage('Игра окончена: соперник сдался!');
 end;
 if (not board.WhiteTurn xor PlayerWhite) and (animation=0)
    and FileExists(moveFileName) then try
  assignFile(f,moveFileName);
  reset(f);
  readln(f,TurnFrom,TurnTo);
  closeFile(f);
  DeleteFile(moveFileName);
  if PlayerWhite then begin
   x:=40+60*(TurnFrom and $F);
   y:=40+60*(7-TurnFrom shr 4);
  end else begin
   x:=40+60*(7-TurnFrom and $F);
   y:=40+60*(TurnFrom shr 4);
  end;
  PBoxMouseDown(sender,mbLeft,[],x,y);
  if PlayerWhite then begin
   x:=40+60*(TurnTo and $F);
   y:=40+60*(7-TurnTo shr 4);
  end else begin
   x:=40+60*(7-TurnTo and $F);
   y:=40+60*(TurnTo shr 4);
  end;
  PBoxMouseDown(sender,mbLeft,[],x,y);
 except
 end;
 if StartBtn.Down and (board.WhiteTurn xor PlayerWhite) and (animation=0)
    and thread.moveReady then begin
  inc(historyPos);
  history[historyPos]:=board;

  DoMove(board,thread.moveFrom,thread.moveTo);
  historySize:=historyPos+1;
  history[historySize]:=board;

  try
   AssignFile(f,moveFileName);
   rewrite(f);
   writeln(f,thread.moveFrom,' ',thread.moveTo);
   closeFile(f);
  except
  end;
  AddLastTurnNote;
  fillchar(selected,sizeof(selected),0);
  animation:=1;
  DrawBoard(sender);
  CheckGameOver;
  Estimate;
  if gameover=0 then
   if board.WhiteTurn then turnWhiteBtn.Down:=true
    else turnBlackBtn.Down:=true;
  thread.moveReady:=false;
 end;
end;

procedure TMainForm.AddLastTurnNote;
var
 i,j,x,y:integer;
 v:byte;
 st,s2:string;
begin
 with board do begin
  x:=lastTurnTo and $F;
  y:=lastTurnTo shr 4;
  v:=field[x,y];
  case v and $F of
   Knight:st:='К';
   Queen:st:='Ф';
   Rook:st:='Л';
   Bishop:st:='С';
   King:st:='Кр';
   Pawn:st:=' ';
  end;
  st:=st+NameCell(lastTurnFrom and $F,lastTurnFrom shr 4);
  if lastPiece<>0 then st:=st+':' else st:=st+'-';
  st:=st+NameCell(lastTurnTo and $F,LastTurnTo shr 4);
  CalcBeatable(board);
  for i:=0 to 7 do
   for j:=0 to 7 do
    if (field[i,j]=KingWhite) and (beatable[i,j] and Black>0) or
       (field[i,j]=KingBlack) and (beatable[i,j] and White>0) then st:=st+'+';
  if (v and $F=King) and (x=LastTurnFrom and $F-2) then st:='0-0-0';
  if (v and $F=King) and (x=LastTurnFrom and $F+2) then st:='0-0';

  while length(st)<7 do st:=st+' ';
  s2:=''; if memo.lines.count<9 then s2:=' ';
  if v and ColorMask=Black then
   memo.Lines[memo.Lines.Count-1]:=memo.Lines[memo.Lines.Count-1]+' '+st
  else
   memo.Lines.Add(s2+inttostr(memo.lines.Count+1)+' '+st);
 end;
end;

procedure TMainForm.CheckGameover;
var
 i,j,k,x,y:integer;
 b:TBoard;
 color,color2:byte;
 check,noMoves:boolean;
 fl:boolean;
 v1,v2:integer;
begin
 if gameover<>0 then exit;
 // повторение позиции
 k:=1;
 for i:=1 to historyPos do
  if CompareBoards(board,history[i])=0 then inc(k);
 if k>=3 then begin
  gameover:=1;
 end;

 CalcBeatable(board);
 if board.WhiteTurn then begin
  color:=white; color2:=black;
 end else begin
  color:=black; color2:=white;
 end;
 check:=false;
 for i:=0 to 7 do
  for j:=0 to 7 do
   if (board.field[i,j]=King+color) and (beatable[i,j] and color2>0) then check:=true;

 noMoves:=true;
 for i:=0 to 7 do
  for j:=0 to 7 do
   if (board.field[i,j] and ColorMask=color) then begin
    GetAvailMoves(board,i+j shl 4);
    for k:=1 to mCount do begin
     b:=Board;
     DoMove(b,i+j shl 4,moves[k]);
     CalcBeatable(b);
     for x:=0 to 7 do
      for y:=0 to 7 do
       if (b.field[x,y]=King+color) and (beatable[x,y] and Color2=0) then noMoves:=false;
    end;
   end;
 if NoMoves then begin
  if not Check then gameover:=1
   else begin
    if color=white then gameover:=2;
    if color=black then gameover:=3;
   end;
 end;
 if gameover=1 then ShowMessage('Игра окончена: пат!');
 if gameover=2 then ShowMessage('Игра окончена: мат белым!');
 if gameover=3 then ShowMessage('Игра окончена: мат черным!');

 if gameover=0 then begin
  fl:=false; v1:=0; v2:=0;
  for i:=0 to 7 do
   for j:=0 to 7 do begin
    if board.field[i,j] and $F=Pawn then fl:=true;
    case board.field[i,j] of
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
   gameover:=1;
   ShowMessage('Игра окончена: ничья');
  end;  
 end;
end;

procedure TMainForm.ClearBtnClick(Sender: TObject);
begin
 InitBoard(board);
 fillchar(board.field,64,0);
 memo.Lines.Clear;
 DrawBoard(sender);
end;

procedure TMainForm.DrawBoard(Sender: TObject);
var
 i,j,k,v:integer;
 c:cardinal;
 x1,y1,x2,y2:integer;
begin
 with PBox.Canvas do begin
  brush.Color:=$B0CADA;
  FillRect(rect(0,0,510,510));
  pen.color:=$202020;
  Rectangle(14,14,496,496);
  for i:=0 to 7 do
   for j:=0 to 7 do begin
    if (i xor j) mod 2=1 then
     brush.color:=BlackFieldColor
    else
     brush.color:=WhiteFieldColor;
    fillRect(rect(15+i*60,15+j*60,75+i*60,75+j*60));
    c:=0;
    k:=j; v:=i;
    if PlayerWhite then k:=7-k else v:=7-i;
    if selected[v,k] and 2>0 then c:=$A0B0E0;
    if selected[v,k] and 1>0 then c:=$A0C0D0;
    if c>0 then
    for k:=0 to 2 do begin
     pen.color:=c;
     c:=c-$101010;
     Rectangle(15+i*60+k,15+j*60+k,75+i*60-k,75+j*60-k);
    end;
   end;
  font.Size:=10;
  font.Style:=[fsBold];
  brush.style:=bsClear;
  if playerWhite then
   for i:=1 to 8 do begin
    TextOut(3,518-i*60,inttostr(i));
    TextOut(499,518-i*60,inttostr(i));
    TextOut(i*60-18,-2,chr(96+i));
    TextOut(i*60-18,494,chr(96+i));
   end
  else
   for i:=1 to 8 do begin
    TextOut(3,518-i*60,inttostr(9-i));
    TextOut(499,518-i*60,inttostr(9-i));
    TextOut(i*60-18,-2,chr(96-i+9));
    TextOut(i*60-18,494,chr(96-i+9));
   end;
  for i:=0 to 7 do
   for k:=0 to 7 do begin
    j:=k; v:=i;
    if PlayerWhite then j:=7-j else v:=7-v;
    if board.field[v,k]<>0 then begin
     if (animation>0) and (v=board.lastTurnTo and $F) and (k=board.lastTurnTo shr 4) then continue;
     Pieces.Draw(PBox.canvas,15+i*60,15+j*60,board.field[v,k] and $f-1+6*byte(board.field[v,k] and $80>0));
    end;
   end;
  if animation>0 then begin
   v:=board.lastTurnTo and $F;
   k:=board.lastTurnTo shr 4;
   x1:=board.lastTurnFrom and $F;
   y1:=board.lastTurnFrom shr 4;
   x2:=board.lastTurnTo and $F;
   y2:=board.lastTurnTo shr 4;
   if playerWhite then begin
    y1:=7-y1; y2:=7-y2;
   end else begin
    x1:=7-x1; x2:=7-x2;
   end;
   i:=15+round(60*(x1+(animation/9)*(x2-x1)));
   j:=15+round(60*(y1+(animation/9)*(y2-y1)));
   Pieces.Draw(PBox.canvas,i,j,board.field[v,k] and $f-1+6*byte(board.field[v,k] and $80>0));
  end;
 end;
end;

procedure TMainForm.Estimate;
var
 r:single;
begin
 EstimatePosition(board,10,true);
 r:=-board.rate;
 status.Panels[0].text:=floattostrF(board.WhiteRate,ffFixed,5,3)+' : '+
  floattostrF(board.BlackRate,ffFixed,5,3)+' = '+
  floattostrF(r,ffFixed,4,3);
end;

initialization
 BlackFieldColor:=StrToInt('$00335C8E');
 WhiteFieldColor:=StrToInt('$008aC5f2');
end.
