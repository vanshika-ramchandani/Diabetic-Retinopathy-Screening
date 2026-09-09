function netra(imagePath)
%NETRA  Entry point. Sets up the path and launches the GUI.
%
%   netra              open the GUI
%   netra('img.jpg')   screen one image at the command line and print the report
%
%   Exists because every module lives in its own folder (m1_quality, m4_grade,
%   app, ...). Calling netraApp directly from matlab/ fails with
%   "Unrecognized function or variable" because app/ is not on the path - which
%   is a bad thing to discover in front of judges.
here = fileparts(mfilename('fullpath'));
addpath(here, ...
        fullfile(here,'lib'), ...
        fullfile(here,'app'), ...
        fullfile(here,'m1_quality'), ...
        fullfile(here,'m2_enhance'), ...
        fullfile(here,'m3_lesions'), ...
        fullfile(here,'m4_grade'), ...
        fullfile(here,'m5_simulink'), ...
        fullfile(here,'tests'));

if nargin == 0
    netraApp();
else
    R = netraScreen(imagePath, struct('verbose',true,'gradcam',true));
    if nargout == 0, clear R; end
end
end
