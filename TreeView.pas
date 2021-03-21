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
 uses Logic, main;

{$R *.dfm}
var
 // индексы эл-тов дерева в qu
 items,itemspos:array[0..20,1..200] of integer;
 selidx:array[0..20] of integer; // индексы выбранных эл-тов (в data)
 selmax:byte;
 saveboard:TBoard;
 saveGameover:integer;

procedure TTreeWnd.BuildTree;
var
 d,i,idx,c,par:integer;
begin
 par:=1;
 for d:=1 to selmax+1 do begin
  for i:=1 to 200 do items[d,i]:=0;
  idx:=data[par].firstChild;
  i:=1;
  while idx>0 do begin
   items[d,i]:=idx;
   inc(i);
   if (d<=selmax) and (selidx[d]=idx) then par:=idx;
   idx:=data[idx].next;
  end;
 end;
end;

procedure TTreeWnd.DrawTree;
var
 i,j,d,idx,c,ypos,add,cx,cy:integer;
 st,st2,st3:string;
 cell1,cell2:byte;
 val:single;
 ch:char;
 hash:int64;
 dbind:integer;
begin
 with Canvas do begin
  brush.Color:=$F0F0F0;
  fillrect(clientrect);
  // 1. вычислим положения эл-тов
  itemspos[0,1]:=ClientHeight div 2;
  ypos:=itemspos[0,1];
  for d:=1 to selmax+1 do begin
   // слой d:
   c:=1;
   while items[d,c]>0 do inc(c);
   dec(c);
   for i:=1 to c do
    itemspos[d,i]:=ypos-((c-1)*18) div 2+(i-1)*18;
   add:=0;
   if itemspos[d,1]<10 then inc(add,10-itemspos[d,1]);
   if itemspos[d,c]>clientHeight-10 then dec(add,itemspos[d,c]-(ClientHeight-10));
   for i:=1 to c do
    inc(itemspos[d,i],add);
   // центр для след слоя
   for i:=1 to c do
    if items[d,i]=selidx[d] then ypos:=itemspos[d,i];
  end;
  // 2. нарисуем линии
  pen.Color:=$606060;
  for d:=1 to selmax+1 do begin
   i:=1;
   while items[d-1,i]>0 do begin
    if items[d-1,i]=selidx[d-1] then begin
     j:=1;
     while items[d,j]>0 do begin
      moveto(25+d*90-45,itemspos[d,j]);
      lineto(25+d*90-35,itemspos[d,j]);
      inc(j);
     end;
     moveto(25+d*90-45,itemspos[d,1]);
     lineto(25+d*90-45,itemspos[d,j-1]);
     moveto(25+d*90-65,itemspos[d-1,i]);
     lineto(25+d*90-45,itemspos[d-1,i]);
    end;
    inc(i);
   end;
  end;
  // 3. нарисуем эл-ты
  font.Size:=8;
  font.Name:='Arial';
  for d:=0 to selmax+1 do begin
   i:=1;
   if d>0 then begin
    // подсветка решающего варианта
    idx:=items[d,i];
    j:=1; // здесь будет решающий
    if data[idx].depth mod 2>0 then val:=-10000 else val:=10000;
    while items[d,i]>0 do begin
     if data[idx].depth mod 2>0 then begin
      if data[items[d,i]].rate>val then begin val:=data[items[d,i]].rate; j:=i; end;
     end else begin
      if data[items[d,i]].rate<val then begin val:=data[items[d,i]].rate; j:=i; end;
     end;
     inc(i);
    end;
   end;
   i:=1;
   while items[d,i]>0 do begin
    if selidx[d]=items[d,i] then brush.color:=$C0D0E0
     else begin
      if data[items[d,i]].flags and $80=0 then brush.color:=$E0E0E0
       else brush.color:=$E0C0C0;
     end;
    if i=j then pen.color:=$A0 else pen.color:=$101010;
    font.color:=pen.color;
    // нет ли элемента в базе?
    hash:=BoardHash(data[items[d,i]]);
    for dbind:=0 to length(dbItems)-1 do
     if dbItems[dbInd].hash=hash then
      font.color:=$8000;

    cx:=25+d*90;
    cy:=itemspos[d,i];
    if d>0 then
     RoundRect(cx-37,cy-7,cx+37,cy+7,5,5)
    else
     RoundRect(cx-22,cy-10,cx+32,cy+10,7,7);
    idx:=items[d,i];
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
    brush.Style:=bsClear;
    TextOut(cx-TextWidth(st) div 2,cy-7,st);
    brush.Style:=bsSolid;
    inc(i);
   end;
  end;

 end;
end;

procedure TTreeWnd.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 board:=saveBoard;
 MainForm.DrawBoard(sender);
 gameover:=saveGameover;
end;

procedure TTreeWnd.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
 i,row,col,v:integer;
begin
 col:=(x+10) div 90;
 if col>selmax+1 then exit;
 i:=1;
 while items[col,i]>0 do begin
  if (y>=itemspos[col,i]-7) and (y<=itemspos[col,i]+7) then begin
   selmax:=col;
   selidx[col]:=items[col,i];
   board:=data[items[col,i]];
   if Button=mbRight then begin
    v:=items[col,i];
    ShowMEssage(inttostr(v)+' '+inttostr(data[v].weight));
   end;
   MainForm.DrawBoard(sender);
   break;
  end;
  inc(i);
 end;
 BuildTree;
 invalidate;
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
 selmax:=0;
 fillchar(selidx,sizeof(selidx),0);
 selidx[0]:=1;
 items[0,1]:=1;
 BuildTree;
 saveBoard:=board;
 saveGameover:=gameover;
 gameover:=4;
end;

end.
