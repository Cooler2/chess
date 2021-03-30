// Окно визуализации дерева поиска: это и для отладки и просто для любопытства
{$R+}
unit TreeView;
interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, ExtCtrls;

type
  TTreeWnd = class(TForm)
    procedure FormPaint(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormResize(Sender: TObject);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    { Private declarations }
  public
    { Public declarations }
    procedure DrawTree;
    procedure BuildTree;
  end;

var
  TreeWnd: TTreeWnd;

implementation
 uses gamedata,main,AI,Apus.MyServis;

{$R *.dfm}
type
 TColumn=record
  items,pos:array of integer;
  procedure Clear;
  procedure Add(v:integer);
 end;
var
 // индексы эл-тов дерева в data [столбец,строка]
 treeData:array of TColumn;
 selIdx:array[0..30] of integer; // индексы цепочки выбранных эл-тов (в data)
 saveGameover:integer;

procedure InitTree;
 begin
  SetLength(treeData,1);
  treeData[0].Clear;
  treeData[0].Add(curBoardIdx);
  selIdx[0]:=curBoardIdx;
 end;

procedure TTreeWnd.BuildTree;
var
 d,i,idx,c,parent:integer;
begin
 parent:=curBoardIdx;
 for d:=1 to high(treeData) do begin
  treeData[i].Clear;
  idx:=data[parent].firstChild;
  while idx>0 do begin
   treeData[i].Add(idx);
   if selidx[d]=idx then parent:=idx;
   idx:=data[idx].nextSibling;
  end;
 end;
end;

procedure UpdateTreePos(clientHeight:integer);
 var
  i,c,d,yPos,vAdd:integer;
 begin
  ypos:=clientHeight div 2;
  treeData[0].pos[0]:=yPos;
  for d:=1 to high(treeData) do
   with treeData[d] do begin // слой d:
    c:=high(items);
    if c<0 then break; // пустой уровень
    for i:=0 to c do
     pos[i]:=ypos-(c*18) div 2+(i-1)*18;
    vAdd:=0;
    if pos[0]<10 then inc(vAdd,10-pos[0]);
    if pos[c]>clientHeight-10 then dec(vAdd,pos[c]-(clientHeight-10));
    for i:=0 to c do
     inc(pos[i],vAdd);
   // центр для след слоя
   for i:=0 to c do
    if items[i]=selidx[d] then
     ypos:=pos[i];
  end;
 end;

procedure DrawTreeLines(canvas:TCanvas);
 var
  i,j,d,y:integer;
 begin
  for d:=1 to high(treeData) do begin
   i:=0;
   // поиск предка в предыдущем уровне
   while treeData[d-1].items[i]>=0 do
    if treeData[d-1].items[i]<>selidx[d-1] then
     inc(i)
    else // отрисовка
     with treeData[d] do begin
      j:=0;
      while items[j]>=0 do begin
       canvas.moveto(25+d*90-45,pos[j]);
       canvas.lineto(25+d*90-35,pos[j]);
       inc(j);
      end;
      // вертикальная линия
      canvas.moveto(25+d*90-45,pos[0]);
      canvas.lineto(25+d*90-45,pos[j-1]);
      // горизонтальная линия
      y:=treeData[d-1].pos[i];
      canvas.moveto(25+d*90-65,y);
      canvas.lineto(25+d*90-45,y);
      break;
     end;
  end;
 end;

procedure DrawTreeNodes(canvas:TCanvas);
 var
  i,j,d,idx,dbInd,cx,cy:integer;
  st,st2,st3:string;
  val:single;
  cell1,cell2:byte;
  hash:int64;
  ch:char;
 begin
  for d:=0 to high(treeData) do
   with treeData[d] do begin
    // выбор решающего варианта для подсветки
    if d>0 then begin
     idx:=items[0];
     j:=0; // здесь будет решающий
     if data[idx].depth mod 2>0 then val:=-10000 else val:=10000;
     for i:=0 to high(items) do begin
      if data[idx].depth mod 2>0 then begin
       if data[items[i]].rate>val then begin val:=data[items[i]].rate; j:=i; end;
      end else begin
       if data[items[i]].rate<val then begin val:=data[items[i]].rate; j:=i; end;
      end;
     end;
    end;

    for i:=0 to high(items) do begin
     if selidx[d]=items[i] then canvas.brush.color:=$C0D0E0
      else begin
       if data[items[i]].flags and movVerified=0 then canvas.brush.color:=$E0E0E0
        else canvas.brush.color:=$E0C0C0;
      end;
     if i=j then canvas.pen.color:=$A0 else canvas.pen.color:=$101010;
     canvas.font.color:=canvas.pen.color;
     // нет ли элемента в базе?
     hash:=BoardHash(data[items[i]]);
     for dbInd:=0 to high(dbItems) do
      if dbItems[dbInd].hash=hash then
       canvas.font.color:=$8000;

     cx:=25+d*90;
     cy:=pos[i];
     if d>0 then
      canvas.RoundRect(cx-37,cy-7,cx+37,cy+7,5,5)
     else
      canvas.RoundRect(cx-22,cy-10,cx+32,cy+10,7,7);
     idx:=items[i];
     if d>0 then begin
      cell1:=data[idx].lastTurnFrom;
      cell2:=data[idx].lastTurnTo;
      if data[idx].flags and movBeat>0 then ch:=':' else ch:='-';
      if data[idx].flags and movCheck>0 then st2:='+' else st2:='';
       st3:=FloatToStrF(data[idx].rate,ffFixed,4,3);
     if abs(data[idx].rate)>210 then
       st3:=FloatToStrF(data[idx].rate,ffFixed,4,0);
      st:=NameCell(cell1 and $F,cell1 shr 4)+ch+NameCell(cell2 and $F,cell2 shr 4)+st2+
       ' '+st3;
     end else
      st:='   Root';
     canvas.brush.Style:=bsClear;
     canvas.TextOut(cx-canvas.TextWidth(st) div 2,cy-7,st);
     canvas.brush.Style:=bsSolid;
    end;
  end;
 end;

procedure TTreeWnd.DrawTree;
begin
 with Canvas do begin
  brush.Color:=$F0F0F0;
  fillrect(clientrect);
  // 1. вычислим положения эл-тов
  UpdateTreePos(clientHeight);
  // 2. нарисуем линии
  pen.Color:=$606060;
  DrawTreeLines(canvas);
  // 3. нарисуем эл-ты
  font.Size:=8;
  font.Name:='Arial';
  DrawTreeNodes(canvas);
 end;
end;

procedure TTreeWnd.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 MainForm.displayBoard:=curBoardIdx;
 MainForm.DrawBoard(sender);
 gameState:=saveGameover;
 ResumeAI;
end;

procedure TTreeWnd.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
 i,row,col,v,idx:integer;
begin
 col:=(x+10) div 90;
 if col>high(treeData) then exit;
 i:=1;
 with treeData[col] do
  for i:=0 to high(items) do
   if (y>=pos[i]-7) and (y<=pos[i]+7) then begin
    idx:=items[i];
    selidx[col]:=idx;
    selIdx[col+1]:=-1;
    mainForm.displayBoard:=idx;
    if Button=mbRight then begin
     v:=items[i];
     ShowMessage(inttostr(v)+' '+data[v].weight.ToString,'');
    end;
    mainForm.DrawBoard(sender);
    break;
   end;
 BuildTree;
 Invalidate;
 MainForm.Estimate;
end;

procedure TTreeWnd.FormPaint(Sender: TObject);
begin
 DrawTree;
end;

procedure TTreeWnd.FormResize(Sender: TObject);
begin
 DrawTree;
end;

procedure TTreeWnd.FormShow(Sender: TObject);
begin
 PauseAI;
 InitTree;
 BuildTree;
 saveGameover:=gameState;
 gameState:=4;
end;

{ TColumn }

procedure TColumn.Add(v:integer);
 var
  n:integer;
 begin
  n:=length(items);
  SetLength(items,n+1);
  SetLength(pos,n+1);
  items[n]:=v;
 end;

procedure TColumn.Clear;
 begin
  SetLength(items,0);
  SetLength(pos,0);
 end;

end.
