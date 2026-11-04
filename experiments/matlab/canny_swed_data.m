%% canny_swed_data.m
% CE671 term paper, Group 15: Canny and five other edge filters on SWED data.
% This version makes NO figures (MATLAB Online had trouble saving figures).
% It only saves numbers (CSV) and plain images (PNG) with imwrite.
% The paper figures are then put together from these files.
%
% HOW TO RUN: keep this file and the two Ashdod .tif files in MATLAB Drive,
% press Run, then zip the folder "canny_data" and send it.

clear; close all; clc; tic;

%% ---------------- SETTINGS ----------------
IMG_FILE = 'S2A_MSIL2A_20200215T082021_N0214_R121_T36SXA_20200215T110825_image_0_0.tif';
LBL_FILE = 'S2A_MSIL2A_20200215T082021_N0214_R121_T36SXA_20200215T110825_label_0_0.tif';
OUT_DIR  = 'canny_data';
iB2 = 2; iB3 = 3; iB4 = 4; iB8 = 8; iB11 = 11;   % SWED band order
TOL = 2;                                          % tolerance in pixels
CANNY_SIGMAS = [1 1.5 2 3 4];
CANNY_HIGHS  = 0.05:0.05:0.70;
LOW_RATIO    = 0.4;
THR_FACTORS  = [0.25 0.5 0.75 1 1.25 1.5 2 2.5 3];
LOG_SIGMAS   = [1 1.5 2 3];
%% ------------------------------------------

if ~isfile(IMG_FILE), IMG_FILE = fullfile('SWED_sample','test','images',IMG_FILE); end
if ~isfile(LBL_FILE), LBL_FILE = fullfile('SWED_sample','test','labels',LBL_FILE); end
if ~exist(OUT_DIR,'dir'), mkdir(OUT_DIR); end

%% 1. Data
I = double(imread(IMG_FILE));
L = imread(LBL_FILE); water = L(:,:,1) > 0;
rgb  = cat(3, stretch(I(:,:,iB4)), stretch(I(:,:,iB3)), stretch(I(:,:,iB2)));
gray = rgb2gray(rgb);
G = I(:,:,iB3); N = I(:,:,iB8); S = I(:,:,iB11);
ndwi  = mat2gray((G-N)./(G+N+eps), [-1 1]);
mndwi = mat2gray((G-S)./(G+S+eps), [-1 1]);
inputs = {gray, ndwi, mndwi}; names = {'Grayscale','NDWI','MNDWI'};
truth = water & imdilate(~water, ones(3));
imwrite(rgb,   fullfile(OUT_DIR,'in_rgb.png'));
imwrite(gray,  fullfile(OUT_DIR,'in_Grayscale.png'));
imwrite(ndwi,  fullfile(OUT_DIR,'in_NDWI.png'));
imwrite(mndwi, fullfile(OUT_DIR,'in_MNDWI.png'));
imwrite(water, fullfile(OUT_DIR,'label_water.png'));
imwrite(truth, fullfile(OUT_DIR,'label_coastline.png'));
fprintf('Step 1/4: data saved (%.0f s). Coastline pixels: %d\n', toc, nnz(truth));

%% 2. Six filters, best setting for each filter and input
filters = {'Roberts','Sobel','Prewitt','Laplacian','LoG','Canny'};
rows = cell(0,6); bestCanny = cell(1,3);
for i = 1:3
    for k = 1:numel(filters)
        [E,P,R,F,p] = best_filter(inputs{i}, filters{k}, truth, TOL, ...
            CANNY_SIGMAS, CANNY_HIGHS, LOW_RATIO, THR_FACTORS, LOG_SIGMAS);
        rows(end+1,:) = {names{i}, filters{k}, p, P, R, F}; %#ok<AGROW>
        imwrite(E, fullfile(OUT_DIR, sprintf('edges_%s_%s.png', names{i}, filters{k})));
        if k == numel(filters), bestCanny{i} = p; end
        fprintf('   %-9s %-9s %-26s P=%.2f R=%.2f F1=%.3f\n', names{i}, filters{k}, p, P, R, F);
    end
end
writetable(cell2table(rows,'VariableNames',{'Input','Filter','BestSetting','Precision','Recall','F1'}), ...
    fullfile(OUT_DIR,'scores_all_filters_all_inputs.csv'));
fprintf('Step 2/4: six filters done (%.0f s)\n', toc);

%% 3. Canny: every sigma and every high threshold on every input
sw = cell(0,7);
for i = 1:3
    for s = CANNY_SIGMAS
        for H = CANNY_HIGHS
            E = edge(inputs{i}, 'canny', [LOW_RATIO*H H], s);
            [P,R,F] = score_edges(E, truth, TOL);
            sw(end+1,:) = {names{i}, s, H, LOW_RATIO*H, P, R, F}; %#ok<AGROW>
        end
    end
end
TS = cell2table(sw,'VariableNames',{'Input','Sigma','High','Low','Precision','Recall','F1'});
writetable(TS, fullfile(OUT_DIR,'canny_sweep_all_settings.csv'));
% best high threshold for each sigma; save those edge maps
tb = cell(0,7);
for i = 1:3
    for s = CANNY_SIGMAS
        r = TS(strcmp(TS.Input,names{i}) & TS.Sigma==s, :);
        [~,j] = max(r.F1);
        tb(end+1,:) = {names{i}, s, r.High(j), r.Low(j), r.Precision(j), r.Recall(j), r.F1(j)}; %#ok<AGROW>
        E = edge(inputs{i}, 'canny', [r.Low(j) r.High(j)], s);
        imwrite(E, fullfile(OUT_DIR, sprintf('sigma_%s_%g.png', names{i}, s)));
    end
end
TB = cell2table(tb,'VariableNames',{'Input','Sigma','BestHigh','Low','Precision','Recall','F1'});
writetable(TB, fullfile(OUT_DIR,'canny_best_per_sigma.csv'));
disp(TB);
fprintf('Step 3/4: Canny sweep done (%.0f s)\n', toc);

%% 4. The five Canny steps on the Grayscale input with its best setting
v = sscanf(bestCanny{1}, 'sigma=%f, high=%f'); sig = v(1); H = v(2); Lo = LOW_RATIO*H;
X = inputs{1};
B = imgaussfilt(X, sig);
[Gx, Gy] = imgradientxy(B, 'sobel');
Gm = hypot(Gx, Gy); Gm = Gm / max(Gm(:));
th = atan2d(Gy, Gx); th(th<0) = th(th<0) + 180;
sec = mod(round(th/45), 4);
Gp = padarray(Gm, [1 1], 0);
nb = @(dr,dc) Gp((2:end-1)+dr, (2:end-1)+dc);
keep = (sec==0 & Gm>=nb(0,1) & Gm>=nb(0,-1)) | (sec==1 & Gm>=nb(1,1) & Gm>=nb(-1,-1)) | ...
       (sec==2 & Gm>=nb(1,0) & Gm>=nb(-1,0)) | (sec==3 & Gm>=nb(1,-1) & Gm>=nb(-1,1));
Nn = Gm .* keep;
strong = Nn >= H; weak = Nn >= Lo & ~strong;
CC = bwlabel(strong | weak, 8); ids = unique(CC(strong)); Efin = ismember(CC, ids(ids>0));
imwrite(B,                 fullfile(OUT_DIR,'step1_blur.png'));
imwrite(mat2gray(abs(Gx)), fullfile(OUT_DIR,'step2_absGx.png'));
imwrite(mat2gray(abs(Gy)), fullfile(OUT_DIR,'step2_absGy.png'));
imwrite(Gm,                fullfile(OUT_DIR,'step2_strength.png'));
imwrite(Nn > 0,            fullfile(OUT_DIR,'step3_thin.png'));
imwrite(strong,            fullfile(OUT_DIR,'step4_strong.png'));
imwrite(weak,              fullfile(OUT_DIR,'step4_weak.png'));
imwrite(Efin,              fullfile(OUT_DIR,'step5_final.png'));
fid = fopen(fullfile(OUT_DIR,'step_settings.txt'),'w');
fprintf(fid, 'Grayscale: sigma=%g high=%g low=%g\n', sig, H, Lo); fclose(fid);
fprintf('Step 4/4: Canny steps saved (%.0f s)\n', toc);
fprintf('\nAll results saved in folder: %s\n', OUT_DIR);

%% ================= FUNCTIONS =================
function y = stretch(x)
    v = sort(x(:)); lo = v(max(1,round(0.02*numel(v)))); hi = v(max(1,round(0.98*numel(v))));
    y = min(max((x-lo)/max(hi-lo,eps),0),1);
end
function [P,R,F] = score_edges(E,T,tol)
    if nnz(E)==0, P=0; R=0; F=0; return; end
    dT = bwdist(T); dE = bwdist(E);
    P = nnz(E & dT<=tol)/nnz(E); R = nnz(T & dE<=tol)/max(nnz(T),1);
    if P+R==0, F=0; else, F=2*P*R/(P+R); end
end
function [Eb,Pb,Rb,Fb,pb] = best_filter(X,name,T,tol,cS,cH,lowR,facs,logS)
    Fb=-1; Eb=false(size(X)); Pb=0; Rb=0; pb='';
    switch name
        case 'Canny'
            for s=cS, for H=cH
                p=sprintf('sigma=%.1f, high=%.2f',s,H); E=run_filter(X,name,p,lowR);
                [P,R,F]=score_edges(E,T,tol); if F>Fb, Fb=F;Pb=P;Rb=R;Eb=E;pb=p; end
            end, end
        case 'LoG'
            for s=logS
                [~,t0]=edge(X,'log',[],s);
                for fa=facs
                    p=sprintf('sigma=%.1f, thr=%.4g',s,fa*t0); E=run_filter(X,name,p,lowR);
                    [P,R,F]=score_edges(E,T,tol); if F>Fb, Fb=F;Pb=P;Rb=R;Eb=E;pb=p; end
                end
            end
        otherwise
            if strcmp(name,'Laplacian'), [~,t0]=edge(X,'zerocross',[],fspecial('laplacian',0));
            else, [~,t0]=edge(X,lower(name)); end
            for fa=facs
                p=sprintf('thr=%.4g',fa*t0); E=run_filter(X,name,p,lowR);
                [P,R,F]=score_edges(E,T,tol); if F>Fb, Fb=F;Pb=P;Rb=R;Eb=E;pb=p; end
            end
    end
end
function E = run_filter(X,name,p,lowR)
    switch name
        case 'Canny', v=sscanf(p,'sigma=%f, high=%f'); E=edge(X,'canny',[lowR*v(2) v(2)],v(1));
        case 'LoG',   v=sscanf(p,'sigma=%f, thr=%f');  E=edge(X,'log',v(2),v(1));
        case 'Laplacian', v=sscanf(p,'thr=%f'); E=edge(X,'zerocross',v,fspecial('laplacian',0));
        otherwise, v=sscanf(p,'thr=%f'); E=edge(X,lower(name),v);
    end
end