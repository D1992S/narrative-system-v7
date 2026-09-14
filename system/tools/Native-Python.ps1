function Invoke-SystemV7PythonUtf8 {
    param([Parameter(Mandatory)][string]$Python,[Parameter(Mandatory)][string]$Script,[string[]]$Arguments=@())
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Python;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false,$true)
    $start.StandardErrorEncoding=[Text.UTF8Encoding]::new($false,$true)
    $start.Environment['PYTHONUTF8']='1';$start.Environment['PYTHONIOENCODING']='utf-8'
    foreach($argument in (@('-B','-X','utf8',$Script)+$Arguments)){$start.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    try{
        if(-not $process.Start()){throw 'PYTHON_START_FAILED'}
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{ExitCode=$process.ExitCode;Stdout=$stdout.GetAwaiter().GetResult();Stderr=$stderr.GetAwaiter().GetResult()}
    }finally{$process.Dispose()}
}
