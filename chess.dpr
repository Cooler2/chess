program chess;

uses
  Forms,
  main in 'main.pas' {MainForm},
  logic in 'logic.pas',
  TreeView in 'TreeView.pas' {TreeWnd};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TTreeWnd, TreeWnd);
  Application.Run;
end.
