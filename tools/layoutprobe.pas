program LayoutProbe;
{$mode objfpc}{$H+}
uses SysUtils;
const OSBIT = '/64'; // Vendor build symbol is unavailable in standalone probes.
{$I records.112}
var
  Config: RecConfig;
begin
  Writeln('Version=', mysVersion);
  Writeln('DataChanged=', mysDataChanged);
  Writeln('RecConfig=', SizeOf(RecConfig));
  Writeln('RecUser=', SizeOf(RecUser));
  Writeln('RecEvent=', SizeOf(RecEvent));
  Writeln('RecFileBase=', SizeOf(RecFileBase));
  Writeln('RecFileList=', SizeOf(RecFileList));
  Writeln('RecMessageBase=', SizeOf(RecMessageBase));
  Writeln('RecEchoMailNode=', SizeOf(RecEchoMailNode));
end.
