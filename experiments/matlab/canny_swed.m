%% canny_swed.m
% CE671 term paper, Group 15: Canny edge detection on SWED Sentinel-2 data
%
% What this script does (all on real SWED data, no synthetic image):
%   1. Reads one SWED test image (12 bands) and its label (water = 1).
%   2. Makes three single-band inputs: Grayscale, NDWI, MNDWI.
%   3. Finds the true coastline from the label.
%   4. Runs six edge filters (Roberts, Sobel, Prewitt, Laplacian, LoG, Canny)
%      on each input, tries a range of settings for each filter, and keeps
%      the setting with the best F1 score (2-pixel tolerance).
%   5. Shows the five Canny steps on the best input.
%   6. Saves all figures (PNG, 300 dpi) and all scores (CSV) in OUT_DIR.
%   7. (Optional) Runs every image in TEST_DIR with the settings found on
%      the first image and saves the average F1 of each filter (Table 6).
%
% Needs: MATLAB R2020a or newer with the Image Processing Toolbox
%        (MATLAB Online has both).
%
% HOW TO RUN
%   - Put this file and the SWED .tif files in one folder (or set the paths).
%   - Set IMG_FILE and LBL_FILE below to the Ashdod image and label.
%   - Press Run. Figures and CSV files appear in the folder OUT_DIR.

clear; close all; clc;

%% ---------------- SETTINGS (change only this part) ----------------
IMG_FILE = fullfile('SWED_sample','test','images','S2A_MSIL2A_20200215T082021_N0214_R121_T36SXA_20200215T110825_image_0_0.tif');
LBL_FILE = fullfile('SWED_sample','test','labels','S2A_MSIL2A_20200215T082021_N0214_R121_T36SXA_20200215T110825_label_0_0.tif');
OUT_DIR  = 'canny_results';

% Optional batch run over the SWED test set (Table 6).
% Put all test *image.tif and *label.tif files in this folder.
% Leave empty ('') to skip.
TEST_DIR = '';

% Band numbers inside the SWED .tif (12 bands). SWED stores the 12
% Sentinel-2 bands in this order:
%   1:B1  2:B2  3:B3  4:B4  5:B5  6:B6  7:B7  8:B8  9:B8A  10:B9  11:B11  12:B12
% If your file uses a different order, change these numbers.
iB2 = 2;   % blue
iB3 = 3;   % green
iB4 = 4;   % red
iB8 = 8;   % near infrared (10 m)
iB11 = 11; % short-wave infrared (20 m)

TOL = 2;   % tolerance in pixels when checking edges against the coastline

% Settings tried for Canny: 5 blur values x 14 high thresholds = 70 per input
CANNY_SIGMAS = [1 1.5 2 3 4];
CANNY_HIGHS  = 0.05:0.05:0.70;
LOW_RATIO    = 0.4;   % low threshold = 0.4 x high threshold (Canny, 1986: 2-3 times)

% Settings tried for the other filters: their automatic threshold times these factors
THR_FACTORS = [0.25 0.5 0.75 1 1.25 1.5 2 2.5 3];
LOG_SIGMAS  = [1 1.5 2 3];

NOTE = 'Data: SWED, UK Hydrographic Office; Sentinel-2, Copernicus/ESA. Not to be used for navigation.';
%% -------------------------------------------------------------------

if ~exist(OUT_DIR, 'dir'), mkdir(OUT_DIR); end

% If the files are not inside SWED_sample/test/..., look for them by name
% in the current folder (e.g. MATLAB Drive)
if ~isfile(IMG_FILE), [~,n,e] = fileparts(IMG_FILE); IMG_FILE = [n e]; end
if ~isfile(LBL_FILE), [~,n,e] = fileparts(LBL_FILE); LBL_FILE = [n e]; end
if ~isfile(IMG_FILE) || ~isfile(LBL_FILE)
    error('Image or label file not found. Put them in the same folder as this script.');
end

%% 1. Read image and label
[inputs, names, rgb, water] = read_swed(IMG_FILE, LBL_FILE, iB2, iB3, iB4, iB8, iB11);
truth = true_coastline(water);
fprintf('Image size: %d x %d. Coastline pixels: %d\n', size(water,1), size(water,2), nnz(truth));


%% 2. Figure: the data and the three inputs
f = figure('Color','w','Position',[50 50 1500 330]);
t = tiledlayout(f,1,5,'TileSpacing','compact','Padding','compact');
nexttile; imshow(rgb);              title('(a) True colour (B4, B3, B2)');
nexttile; imshow(inputs{1});        title('(b) Grayscale');
nexttile; imshow(inputs{2});        title('(c) NDWI');
nexttile; imshow(inputs{3});        title('(d) MNDWI');
nexttile; imshow(overlay_lines(double(water)*0.6+0.2, truth, [], [])); title('(e) Label and true coastline (green)');
add_note(t, NOTE);
save_fig(f, fullfile(OUT_DIR, 'figA_data_and_inputs.png'));


%% 3. Six filters on each input: search settings, keep the best F1
filters = {'Roberts','Sobel','Prewitt','Laplacian','LoG','Canny'};
nF = numel(filters); nI = numel(inputs);
best = struct();
rows = cell(0, 6);
for i = 1:nI
    X = inputs{i};
    for k = 1:nF
        [E, P, R, F, param] = best_filter(X, filters{k}, truth, TOL, ...
            CANNY_SIGMAS, CANNY_HIGHS, LOW_RATIO, THR_FACTORS, LOG_SIGMAS);
        best(i,k).E = E; best(i,k).P = P; best(i,k).R = R; best(i,k).F = F; best(i,k).param = param;
        rows(end+1,:) = {names{i}, filters{k}, param, P, R, F}; %#ok<AGROW>
        fprintf('%-9s %-9s %-28s P=%.2f R=%.2f F1=%.3f\n', names{i}, filters{k}, param, P, R, F);
    end
end
T = cell2table(rows, 'VariableNames', {'Input','Filter','BestSetting','Precision','Recall','F1'});
writetable(T, fullfile(OUT_DIR, 'scores_all_filters_all_inputs.csv'));

% Best input for Canny
cannyF = arrayfun(@(i) best(i,nF).F, 1:nI);
[~, bi] = max(cannyF);
fprintf('\nBest input for Canny: %s (F1 = %.3f)\n', names{bi}, cannyF(bi));

%% 4. Figure: Canny on the three inputs (green = correct, red = extra, blue = missed)
f = figure('Color','w','Position',[50 50 1200 420]);
t = tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');
for i = 1:nI
    nexttile;
    [m, x, ms] = check_edges(best(i,nF).E, truth, TOL);
    imshow(overlay_lines(inputs{i}*0.6, m, x, ms));
    title(sprintf('(%c) %s, F1 = %.2f', 'a'+i-1, names{i}, best(i,nF).F));
end
add_note(t, NOTE);
save_fig(f, fullfile(OUT_DIR, 'figB_canny_three_inputs.png'));

%% 5. Figure: six filters on the best input
X = inputs{bi};
f = figure('Color','w','Position',[50 50 1200 800]);
t = tiledlayout(f,2,3,'TileSpacing','compact','Padding','compact');
for k = 1:nF
    nexttile; imshow(~best(bi,k).E);   % black edges on white
    title(sprintf('(%c) %s, F1 = %.2f', 'a'+k-1, filters{k}, best(bi,k).F));
end
title(t, sprintf('Six edge filters on the %s input', names{bi}));
add_note(t, NOTE);
save_fig(f, fullfile(OUT_DIR, 'figC_six_filters.png'));

% Same, coloured by correct / extra / missed
f = figure('Color','w','Position',[50 50 1200 800]);
t = tiledlayout(f,2,3,'TileSpacing','compact','Padding','compact');
for k = 1:nF
    nexttile;
    [m, x, ms] = check_edges(best(bi,k).E, truth, TOL);
    imshow(overlay_lines(X*0.6, m, x, ms));
    title(sprintf('(%c) %s, F1 = %.2f', 'a'+k-1, filters{k}, best(bi,k).F));
end
title(t, 'Green = correct edge, red = extra edge, blue = missed coastline');
add_note(t, NOTE);
save_fig(f, fullfile(OUT_DIR, 'figD_six_filters_checked.png'));


%% 6. The five Canny steps on the best input, with its best setting
tok = sscanf(best(bi,nF).param, 'sigma=%f, high=%f');
sigma = tok(1); H = tok(2); L = LOW_RATIO*H;
S = canny_steps(X, sigma, H, L);

% Sobel Gx, Gy, G on the blurred image
f = figure('Color','w','Position',[50 50 1200 420]);
t = tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');
nexttile; imshow(abs(S.Gx), []); title('(a) |Gx| (change from left to right)');
nexttile; imshow(abs(S.Gy), []); title('(b) |Gy| (change from top to bottom)');
nexttile; imshow(S.G, []);       title('(c) Edge strength G');
add_note(t, NOTE);
save_fig(f, fullfile(OUT_DIR, 'figE_sobel_gx_gy.png'));

% Steps 1 to 5 in one figure
f = figure('Color','w','Position',[50 50 1500 900]);
t = tiledlayout(f,2,3,'TileSpacing','compact','Padding','compact');
nexttile; imshow(X);              title(sprintf('(a) Input: %s', names{bi}));
nexttile; imshow(S.B);            title(sprintf('(b) Step 1: blur, \\sigma = %.1f', sigma));
nexttile; imshow(S.G, []);        title('(c) Step 2: edge strength G');
nexttile; imshow(S.N > 0);        title('(d) Step 3: thinning (non-maximum suppression)');
sw = repmat(X*0.4, [1 1 3]);
sw = paint(sw, S.weak,   [1 1 0]);
sw = paint(sw, S.strong, [1 0 0]);
nexttile; imshow(sw);             title(sprintf('(e) Step 4: strong (red, \\geq%.2f) and weak (yellow, \\geq%.2f)', H, L));
nexttile; imshow(~S.E);           title('(f) Step 5: final edges after hysteresis');
add_note(t, NOTE);
save_fig(f, fullfile(OUT_DIR, 'figF_canny_five_steps.png'));

% Also save each step as its own PNG (in case single figures are wanted)
imwrite(X,                    fullfile(OUT_DIR,'step0_input.png'));
imwrite(S.B,                  fullfile(OUT_DIR,'step1_blur.png'));
imwrite(mat2gray(S.G),        fullfile(OUT_DIR,'step2_edge_strength.png'));
imwrite(S.N > 0,              fullfile(OUT_DIR,'step3_thinning.png'));
imwrite(sw,                   fullfile(OUT_DIR,'step4_strong_weak.png'));
imwrite(~S.E,                 fullfile(OUT_DIR,'step5_final.png'));

% Check: our step-by-step Canny against MATLAB's own edge(...,'canny')
[~,~,Fown] = score_edges(S.E, truth, TOL);
fprintf('Step-by-step Canny F1 = %.3f (MATLAB edge(): %.3f)\n', Fown, best(bi,nF).F);

% Checking figure: Canny edges, true coastline, both together
[m, x, ms] = check_edges(best(bi,nF).E, truth, TOL);
f = figure('Color','w','Position',[50 50 1200 420]);
t = tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');
nexttile; imshow(~best(bi,nF).E); title('(a) Canny edges');
nexttile; imshow(~truth);         title('(b) True coastline from the label');
nexttile; imshow(overlay_lines(X*0.6, m, x, ms));
title(sprintf('(c) Green = correct, red = extra, blue = missed (P = %.2f, R = %.2f)', best(bi,nF).P, best(bi,nF).R));
add_note(t, NOTE);
save_fig(f, fullfile(OUT_DIR, 'figG_checking_edges.png'));

%% 7. Optional: all test images with fixed settings (Table 6)
if ~isempty(TEST_DIR)
    files = dir(fullfile(TEST_DIR, '*image*.tif'));
    nT = numel(files);
    F1 = nan(nT, nF);
    imgNames = cell(nT,1);
    for n = 1:nT
        imgPath = fullfile(TEST_DIR, files(n).name);
        lblPath = fullfile(TEST_DIR, strrep(files(n).name, 'image', 'label'));
        if ~isfile(lblPath), fprintf('No label for %s, skipped\n', files(n).name); continue; end
        [inp, ~, ~, w] = read_swed(imgPath, lblPath, iB2, iB3, iB4, iB8, iB11);
        tr = true_coastline(w);
        if nnz(tr) == 0, fprintf('No coastline in %s, skipped\n', files(n).name); continue; end
        Xn = inp{bi};
        for k = 1:nF
            E = run_filter(Xn, filters{k}, best(bi,k).param, LOW_RATIO);
            [~,~,F1(n,k)] = score_edges(E, tr, TOL);
        end
        imgNames{n} = files(n).name;
        fprintf('%3d/%d %s done\n', n, nT, files(n).name);
    end
    Tb = array2table(F1, 'VariableNames', filters);
    Tb = addvars(Tb, imgNames, 'Before', 1, 'NewVariableNames', 'Image');
    writetable(Tb, fullfile(OUT_DIR, 'table6_test_set_F1_per_image.csv'));
    meanF1 = mean(F1, 1, 'omitnan');
    Ts = table(filters', meanF1', sum(~isnan(F1),1)', 'VariableNames', {'Filter','MeanF1','NumImages'});
    writetable(Ts, fullfile(OUT_DIR, 'table6_test_set_mean_F1.csv'));
    disp(Ts);
end

fprintf('\nAll results saved in folder: %s\n', OUT_DIR);

%% ======================= LOCAL FUNCTIONS =======================

function [inputs, names, rgb, water] = read_swed(imgFile, lblFile, iB2, iB3, iB4, iB8, iB11)
    I = double(read_tif(imgFile));
    L = read_tif(lblFile);
    if size(I,3) ~= 12
        warning('%s has %d bands, not 12. Check the band numbers in SETTINGS.', imgFile, size(I,3));
    end
    water = L(:,:,1) > 0;
    % True colour, each band stretched between its 2nd and 98th percentile
    rgb = cat(3, stretch(I(:,:,iB4)), stretch(I(:,:,iB3)), stretch(I(:,:,iB2)));
    gray = rgb2gray(rgb);
    G = I(:,:,iB3); N = I(:,:,iB8); S = I(:,:,iB11);
    ndwi  = (G - N) ./ (G + N + eps);
    mndwi = (G - S) ./ (G + S + eps);
    % Index values run from -1 to +1; map them to 0..1 for the filters
    inputs = {gray, mat2gray(ndwi, [-1 1]), mat2gray(mndwi, [-1 1])};
    names  = {'Grayscale','NDWI','MNDWI'};
end

function A = read_tif(file)
    try
        A = imread(file);
    catch
        tf = Tiff(file, 'r'); A = read(tf); close(tf);
    end
end

function y = stretch(x)
    v = sort(x(:));
    lo = v(max(1, round(0.02*numel(v))));
    hi = v(max(1, round(0.98*numel(v))));
    y = min(max((x - lo) / max(hi - lo, eps), 0), 1);
end

function T = true_coastline(water)
    % Water pixels that touch a land pixel (8-neighbours) = the coastline
    T = water & imdilate(~water, ones(3));
end

function [m, x, ms] = check_edges(E, T, tol)
    dT = bwdist(T); dE = bwdist(E);
    m  = E & (dT <= tol);      % correct edge
    x  = E & ~m;               % extra edge
    ms = T & (dE > tol);       % missed coastline
end

function [P, R, F] = score_edges(E, T, tol)
    if nnz(E) == 0, P = 0; R = 0; F = 0; return; end
    dT = bwdist(T); dE = bwdist(E);
    P = nnz(E & dT <= tol) / nnz(E);
    R = nnz(T & dE <= tol) / max(nnz(T), 1);
    if P + R == 0, F = 0; else, F = 2*P*R/(P + R); end
end

function [Ebest, Pb, Rb, Fb, pbest] = best_filter(X, name, T, tol, cS, cH, lowR, facs, logS)
    Fb = -1; Ebest = false(size(X)); Pb = 0; Rb = 0; pbest = '';
    switch name
        case 'Canny'
            for s = cS
                for H = cH
                    p = sprintf('sigma=%.1f, high=%.2f', s, H);
                    E = run_filter(X, name, p, lowR);
                    [P,R,F] = score_edges(E, T, tol);
                    if F > Fb, Fb=F; Pb=P; Rb=R; Ebest=E; pbest=p; end
                end
            end
        case 'LoG'
            for s = logS
                [~, t0] = edge(X, 'log', [], s);
                for fa = facs
                    p = sprintf('sigma=%.1f, thr=%.4g', s, fa*t0);
                    E = run_filter(X, name, p, lowR);
                    [P,R,F] = score_edges(E, T, tol);
                    if F > Fb, Fb=F; Pb=P; Rb=R; Ebest=E; pbest=p; end
                end
            end
        otherwise   % Roberts, Sobel, Prewitt, Laplacian
            if strcmp(name, 'Laplacian')
                [~, t0] = edge(X, 'zerocross', [], fspecial('laplacian', 0));
            else
                [~, t0] = edge(X, lower(name));
            end
            for fa = facs
                p = sprintf('thr=%.4g', fa*t0);
                E = run_filter(X, name, p, lowR);
                [P,R,F] = score_edges(E, T, tol);
                if F > Fb, Fb=F; Pb=P; Rb=R; Ebest=E; pbest=p; end
            end
    end
end

function E = run_filter(X, name, p, lowR)
    switch name
        case 'Canny'
            v = sscanf(p, 'sigma=%f, high=%f');
            E = edge(X, 'canny', [lowR*v(2) v(2)], v(1));
        case 'LoG'
            v = sscanf(p, 'sigma=%f, thr=%f');
            E = edge(X, 'log', v(2), v(1));
        case 'Laplacian'
            v = sscanf(p, 'thr=%f');
            E = edge(X, 'zerocross', v, fspecial('laplacian', 0));
        otherwise
            v = sscanf(p, 'thr=%f');
            E = edge(X, lower(name), v);
    end
end

function S = canny_steps(X, sigma, H, L)
    % Canny written out step by step, so each step can be shown
    S.B = imgaussfilt(X, sigma);                          % Step 1: blur
    [S.Gx, S.Gy] = imgradientxy(S.B, 'sobel');            % Step 2: Sobel
    G = hypot(S.Gx, S.Gy);
    S.G = G / max(G(:));                                  % edge strength, 0..1
    th = atan2d(S.Gy, S.Gx);                              % gradient direction
    th(th < 0) = th(th < 0) + 180;
    sec = mod(round(th / 45), 4);                         % 0:0, 1:45, 2:90, 3:135 deg
    Gp = padarray(S.G, [1 1], 0);
    nb = @(dr, dc) Gp((2:end-1) + dr, (2:end-1) + dc);    % neighbour at (row+dr, col+dc)
    % y (rows) increases downwards, so 45 deg points right-and-down
    keep = (sec == 0 & S.G >= nb(0, 1) & S.G >= nb(0,-1)) | ...
           (sec == 1 & S.G >= nb(1, 1) & S.G >= nb(-1,-1)) | ...
           (sec == 2 & S.G >= nb(1, 0) & S.G >= nb(-1, 0)) | ...
           (sec == 3 & S.G >= nb(1,-1) & S.G >= nb(-1, 1));
    S.N = S.G .* keep;                                    % Step 3: thinning
    S.strong = S.N >= H;                                  % Step 4: two thresholds
    S.weak   = S.N >= L & ~S.strong;
    cand = S.strong | S.weak;                             % Step 5: hysteresis
    CC = bwlabel(cand, 8);
    ids = unique(CC(S.strong));
    S.E = ismember(CC, ids(ids > 0));
end

function O = overlay_lines(base, m, x, ms)
    O = repmat(base, [1 1 3]);
    if ~isempty(m),  O = paint(O, m,  [0 0.8 0]); end
    if ~isempty(x),  O = paint(O, x,  [1 0 0]);   end
    if ~isempty(ms), O = paint(O, ms, [0 0.3 1]); end
end

function O = paint(O, mask, c)
    for ch = 1:3
        tmp = O(:,:,ch); tmp(mask) = c(ch); O(:,:,ch) = tmp;
    end
end

function add_note(t, note)
    xlabel(t, note, 'FontSize', 8, 'Color', [0.3 0.3 0.3]);
end

function save_fig(f, file)
    exportgraphics(f, file, 'Resolution', 300);
end