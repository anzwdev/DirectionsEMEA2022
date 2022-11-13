codeunit 58100 "ISV2 Process Items"
{

    procedure ProcessItems()
    var
        ISV2ItemImportBuffer: Record "ISV2 Item Import Buffer";
    begin
        ISV2ItemImportBuffer.Reset();
        if (ISV2ItemImportBuffer.FindSet(true)) then
            repeat
                ProcessItem(ISV2ItemImportBuffer);
            until (ISV2ItemImportBuffer.Next() = 0);
    end;

    local procedure ProcessItem(var ISV2ItemImportBuffer: Record "ISV2 Item Import Buffer")
    begin
        OnBeforeProcessItem(ISV2ItemImportBuffer);

        OnAfterProcessItem(ISV2ItemImportBuffer);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeProcessItem(var ISV2ItemImportBuffer: Record "ISV2 Item Import Buffer")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterProcessItem(var ISV2ItemImportBuffer: Record "ISV2 Item Import Buffer")
    begin
    end;
}
