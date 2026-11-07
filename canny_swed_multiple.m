%% canny_swed_multiple.m
% CE671 Term Paper, Group 15
% Batch Canny and edge-filter comparison on multiple SWED Sentinel-2 images.
%
% INPUT:
%   IMAGE_DIR: folder containing files whose names include "image"
%   LABEL_DIR: folder containing corresponding files whose names include "label"
%   The image and label filenames must match after replacing "image" with "label".
%
% OUTPUT:
%   OUT_DIR/
%       Image_1_name/     figures, edge maps and per-image CSV
%       Image_2_name/
%       ...
%       all_images_scores.csv
%       mean_F1_by_filter_and_input.csv
%
% Requires MATLAB R2020a+ and Image Processing Toolbox.

clear; close all; clc;
tic;

%% ---------------- SETTINGS: EDIT THIS SECTION ----------------
IMAGE_DIR = fullfile('SWED','test','images');
LABEL_DIR = fullfile('SWED','test','labels');
OUT_DIR   = 'canny_multiple_results';

% SWED Sentinel-2 band order:
% 1:B1 2:B2 3:B3 4:B4 5:B5 6:B6 7:B7 8:B8 9:B8A 10:B9 11:B11 12:B12
iB2 = 2;       % Blue
iB3 = 3;       % Green
iB4 = 4;       % Red
iB8 = 8;       % Near infrared
iB11 = 11;     % Short-wave infrared

TOL = 2;                         % coastline matching tolerance in pixels
CANNY_SIGMAS = [1 1.5 2 3 4];
CANNY_HIGHS  = 0.05:0.05:0.70;
LOW_RATIO = 0.4;
THR_FACTORS = [0.25 0.5 0.75 1 1.25 1.5 2 2.5 3];
LOG_SIGMAS = [1 1.5 2 3];

% Set true to save all figures. Set false to save only numerical CSV and PNG maps.
SAVE_FIGURES = true;

NOTE = 'Data: SWED, UK Hydrographic Office; Sentinel-2, Copernicus/ESA. Not for navigation.';
%% -------------------------------------------------------------

if ~isfolder(IMAGE_DIR)
    error('Image folder not found: %s', IMAGE_DIR);
end
if ~isfolder(LABEL_DIR)
    error('Label folder not found: %s', LABEL_DIR);
end
if ~isfolder(OUT_DIR), mkdir(OUT_DIR); end

imageFiles = dir(fullfile(IMAGE_DIR, '*image*.tif'));
if isempty(imageFiles)
    imageFiles = dir(fullfile(IMAGE_DIR, '*image*.tiff'));
end
if isempty(imageFiles)
    error('No *image*.tif or *image*.tiff files found in IMAGE_DIR.');
end

filters = {'Roberts','Sobel','Prewitt','Laplacian','LoG','Canny'};
allRows = cell(0,8);
summaryRows = cell(0,4);
processed = 0;

fprintf('Found %d image file(s).\n', numel(imageFiles));

%% ---------------- PROCESS EACH IMAGE ----------------
for n = 1:numel(imageFiles)

    imgName = imageFiles(n).name;
    imgPath = fullfile(IMAGE_DIR, imgName);

    % Find corresponding label by replacing "image" with "label".
    lblName = regexprep(imgName, 'image', 'label', 'ignorecase');
    lblPath = fullfile(LABEL_DIR, lblName);

    if ~isfile(lblPath)
        fprintf('Skipping %s: matching label not found (%s).\n', imgName, lblName);
        continue;
    end

    [~, baseName] = fileparts(imgName);
    imageOut = fullfile(OUT_DIR, safe_name(baseName));
    if ~isfolder(imageOut), mkdir(imageOut); end

    fprintf('\n====================================================\n');
    fprintf('Processing image %d/%d: %s\n', n, numel(imageFiles), imgName);

    try
        [inputs, names, rgb, water] = read_swed(imgPath, lblPath, ...
            iB2, iB3, iB4, iB8, iB11);
    catch ME
        fprintf('Could not read %s. Skipped. Reason: %s\n', imgName, ME.message);
        continue;
    end

    truth = true_coastline(water);
    if nnz(truth) == 0
        fprintf('No coastline pixels found in %s. Skipped.\n', imgName);
        continue;
    end

    fprintf('Image size: %d x %d; coastline pixels: %d\n', ...
        size(water,1), size(water,2), nnz(truth));

    % Save input data.
    imwrite(rgb, fullfile(imageOut,'input_true_colour.png'));
    imwrite(inputs{1}, fullfile(imageOut,'input_grayscale.png'));
    imwrite(inputs{2}, fullfile(imageOut,'input_NDWI.png'));
    imwrite(inputs{3}, fullfile(imageOut,'input_MNDWI.png'));
    imwrite(water, fullfile(imageOut,'label_water.png'));
    imwrite(truth, fullfile(imageOut,'label_true_coastline.png'));

    if SAVE_FIGURES
        f = figure('Visible','off','Color','w','Position',[50 50 1500 350]);
        t = tiledlayout(f,1,5,'TileSpacing','compact','Padding','compact');
        nexttile; imshow(rgb); title('(a) True colour');
        nexttile; imshow(inputs{1}); title('(b) Grayscale');
        nexttile; imshow(inputs{2}); title('(c) NDWI');
        nexttile; imshow(inputs{3}); title('(d) MNDWI');
        nexttile; imshow(overlay_lines(double(water)*0.6+0.2,truth,[],[]));
        title('(e) Label and coastline');
        add_note(t,NOTE);
        save_fig(f,fullfile(imageOut,'figA_data_and_inputs.png'));
        close(f);
    end

    %% Run six filters on three inputs and optimise settings for this image.
    nF = numel(filters);
    nI = numel(inputs);
    best = struct();
    imageRows = cell(0,8);

    for i = 1:nI
        X = inputs{i};
        for k = 1:nF
            [E,P,R,F,param] = best_filter(X,filters{k},truth,TOL, ...
                CANNY_SIGMAS,CANNY_HIGHS,LOW_RATIO,THR_FACTORS,LOG_SIGMAS);

            best(i,k).E = E;
            best(i,k).P = P;
            best(i,k).R = R;
            best(i,k).F = F;
            best(i,k).param = param;

            imageRows(end+1,:) = {imgName,names{i},filters{k},param,P,R,F,nnz(E)}; %#ok<AGROW>
            allRows(end+1,:) = imageRows(end,:); %#ok<AGROW>

            fprintf('%-9s %-9s P=%.3f R=%.3f F1=%.3f\n', ...
                names{i},filters{k},P,R,F);

            imwrite(E,fullfile(imageOut,sprintf('edges_%s_%s.png',names{i},filters{k})));
        end
    end

    T = cell2table(imageRows,'VariableNames', ...
        {'Image','Input','Filter','BestSetting','Precision','Recall','F1','EdgePixels'});
    writetable(T,fullfile(imageOut,'scores_this_image.csv'));

    %% Identify best input for Canny for this image.
    cannyF = arrayfun(@(i) best(i,nF).F,1:nI);
    [~,bi] = max(cannyF);
    fprintf('Best Canny input: %s (F1 = %.3f)\n',names{bi},cannyF(bi));

    %% Canny comparison across the three inputs.
    if SAVE_FIGURES
        f = figure('Visible','off','Color','w','Position',[50 50 1200 420]);
        t = tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');
        for i = 1:nI
            nexttile;
            [m,x,ms] = check_edges(best(i,nF).E,truth,TOL);
            imshow(overlay_lines(inputs{i}*0.6,m,x,ms));
            title(sprintf('%s, F1 = %.2f',names{i},best(i,nF).F));
        end
        add_note(t,NOTE);
        save_fig(f,fullfile(imageOut,'figB_canny_three_inputs.png'));
        close(f);

        %% Six filters on the best Canny input.
        f = figure('Visible','off','Color','w','Position',[50 50 1200 800]);
        t = tiledlayout(f,2,3,'TileSpacing','compact','Padding','compact');
        for k = 1:nF
            nexttile; imshow(~best(bi,k).E);
            title(sprintf('%s, F1 = %.2f',filters{k},best(bi,k).F));
        end
        title(t,sprintf('Six filters on %s',names{bi}));
        add_note(t,NOTE);
        save_fig(f,fullfile(imageOut,'figC_six_filters.png'));
        close(f);

        f = figure('Visible','off','Color','w','Position',[50 50 1200 800]);
        t = tiledlayout(f,2,3,'TileSpacing','compact','Padding','compact');
        for k = 1:nF
            nexttile;
            [m,x,ms] = check_edges(best(bi,k).E,truth,TOL);
            imshow(overlay_lines(inputs{bi}*0.6,m,x,ms));
            title(sprintf('%s, F1 = %.2f',filters{k},best(bi,k).F));
        end
        title(t,'Green = correct; red = extra; blue = missed coastline');
        add_note(t,NOTE);
        save_fig(f,fullfile(imageOut,'figD_six_filters_checked.png'));
        close(f);
    end

    %% Five Canny stages using the best Canny setting for the best input.
    tok = sscanf(best(bi,nF).param,'sigma=%f, high=%f');
    sigma = tok(1);
    H = tok(2);
    L = LOW_RATIO*H;
    S = canny_steps(inputs{bi},sigma,H,L);

    imwrite(inputs{bi},fullfile(imageOut,'step0_input.png'));
    imwrite(S.B,fullfile(imageOut,'step1_blur.png'));
    imwrite(mat2gray(S.G),fullfile(imageOut,'step2_edge_strength.png'));
    imwrite(S.N>0,fullfile(imageOut,'step3_thinning.png'));

    sw = repmat(inputs{bi}*0.4,[1 1 3]);
    sw = paint(sw,S.weak,[1 1 0]);
    sw = paint(sw,S.strong,[1 0 0]);
    imwrite(sw,fullfile(imageOut,'step4_strong_weak.png'));
    imwrite(~S.E,fullfile(imageOut,'step5_final_edges.png'));

    fid = fopen(fullfile(imageOut,'canny_best_setting.txt'),'w');
    fprintf(fid,'Best input: %s\nSigma: %g\nHigh threshold: %g\nLow threshold: %g\n', ...
        names{bi},sigma,H,L);
    fclose(fid);

    if SAVE_FIGURES
        f = figure('Visible','off','Color','w','Position',[50 50 1500 900]);
        t = tiledlayout(f,2,3,'TileSpacing','compact','Padding','compact');
        nexttile; imshow(inputs{bi}); title(sprintf('(a) Input: %s',names{bi}));
        nexttile; imshow(S.B); title(sprintf('(b) Gaussian blur, sigma = %.1f',sigma));
        nexttile; imshow(S.G,[]); title('(c) Gradient magnitude');
        nexttile; imshow(S.N>0); title('(d) Non-maximum suppression');
        nexttile; imshow(sw); title('(e) Strong (red), weak (yellow)');
        nexttile; imshow(~S.E); title('(f) Final edges after hysteresis');
        add_note(t,NOTE);
        save_fig(f,fullfile(imageOut,'figE_canny_five_steps.png'));
        close(f);
    end

    [~,~,Fmanual] = score_edges(S.E,truth,TOL);
    fprintf('Manual step-by-step Canny F1 = %.3f; built-in Canny F1 = %.3f\n', ...
        Fmanual,best(bi,nF).F);

    % Store one summary row per image/filter, using the best input per filter.
    for k = 1:nF
        summaryRows(end+1,:) = {imgName,filters{k},best(bi,k).F,nF}; %#ok<AGROW>
    end

    processed = processed + 1;
    fprintf('Finished %s (elapsed %.1f seconds).\n',imgName,toc);
end

%% ---------------- SAVE COMBINED RESULTS ----------------
if isempty(allRows)
    error('No images were successfully processed. Check paths and image-label filenames.');
end

Tall = cell2table(allRows,'VariableNames', ...
    {'Image','Input','Filter','BestSetting','Precision','Recall','F1','EdgePixels'});
writetable(Tall,fullfile(OUT_DIR,'all_images_scores.csv'));

% Mean F1 for every filter/input combination across processed images.
[G, inputGroup, filterGroup] = findgroups(Tall.Input,Tall.Filter);
meanF1 = splitapply(@mean,Tall.F1,G);
stdF1 = splitapply(@std,Tall.F1,G);
numImages = splitapply(@numel,Tall.F1,G);
Tmean = table(inputGroup,filterGroup,meanF1,stdF1,numImages, ...
    'VariableNames',{'Input','Filter','MeanF1','StdF1','NumImages'});
writetable(Tmean,fullfile(OUT_DIR,'mean_F1_by_filter_and_input.csv'));

% Mean F1 for each filter using the best Canny input selected per image.
% Note: the per-filter values below are taken from the best input selected
% by Canny for that image, matching the filter comparison figures.
if ~isempty(summaryRows)
    Tsummary = cell2table(summaryRows,'VariableNames', ...
        {'Image','Filter','F1_on_best_Canny_input','Unused'});
    Tsummary.Unused = [];
    writetable(Tsummary,fullfile(OUT_DIR,'F1_on_best_Canny_input_per_image.csv'));
end

fprintf('\n====================================================\n');
fprintf('Successfully processed %d image(s).\n',processed);
fprintf('All outputs saved in: %s\n',OUT_DIR);
fprintf('Total elapsed time: %.1f seconds\n',toc);

%% ======================== LOCAL FUNCTIONS ========================

function [inputs,names,rgb,water] = read_swed(imgFile,lblFile,iB2,iB3,iB4,iB8,iB11)
    I = double(read_tif(imgFile));
    L = read_tif(lblFile);
    if size(I,3) < max([iB2 iB3 iB4 iB8 iB11])
        error('Image does not contain all requested bands.');
    end
    if size(L,1) ~= size(I,1) || size(L,2) ~= size(I,2)
        error('Image and label dimensions do not match.');
    end
    water = L(:,:,1) > 0;
    rgb = cat(3,stretch(I(:,:,iB4)),stretch(I(:,:,iB3)),stretch(I(:,:,iB2)));
    gray = rgb2gray(rgb);
    G = I(:,:,iB3); N = I(:,:,iB8); S = I(:,:,iB11);
    ndwi = (G-N)./(G+N+eps);
    mndwi = (G-S)./(G+S+eps);
    inputs = {gray,mat2gray(ndwi,[-1 1]),mat2gray(mndwi,[-1 1])};
    names = {'Grayscale','NDWI','MNDWI'};
end

function A = read_tif(file)
    try
        A = imread(file);
    catch
        tf = Tiff(file,'r');
        A = read(tf);
        close(tf);
    end
end

function y = stretch(x)
    v = sort(x(:));
    lo = v(max(1,round(0.02*numel(v))));
    hi = v(max(1,round(0.98*numel(v))));
    y = min(max((x-lo)/max(hi-lo,eps),0),1);
end

function T = true_coastline(water)
    T = water & imdilate(~water,ones(3));
end

function [m,x,ms] = check_edges(E,T,tol)
    dT = bwdist(T);
    dE = bwdist(E);
    m = E & (dT<=tol);
    x = E & ~m;
    ms = T & (dE>tol);
end

function [P,R,F] = score_edges(E,T,tol)
    if nnz(E)==0
        P=0; R=0; F=0; return;
    end
    dT = bwdist(T);
    dE = bwdist(E);
    P = nnz(E & dT<=tol)/nnz(E);
    R = nnz(T & dE<=tol)/max(nnz(T),1);
    if P+R==0, F=0; else, F=2*P*R/(P+R); end
end

function [Ebest,Pb,Rb,Fb,pbest] = best_filter(X,name,T,tol,cS,cH,lowR,facs,logS)
    Fb=-1; Ebest=false(size(X)); Pb=0; Rb=0; pbest='';
    switch name
        case 'Canny'
            for s=cS
                for H=cH
                    p=sprintf('sigma=%.1f, high=%.2f',s,H);
                    E=run_filter(X,name,p,lowR);
                    [P,R,F]=score_edges(E,T,tol);
                    if F>Fb, Fb=F; Pb=P; Rb=R; Ebest=E; pbest=p; end
                end
            end
        case 'LoG'
            for s=logS
                [~,t0]=edge(X,'log',[],s);
                for fa=facs
                    p=sprintf('sigma=%.1f, thr=%.4g',s,fa*t0);
                    E=run_filter(X,name,p,lowR);
                    [P,R,F]=score_edges(E,T,tol);
                    if F>Fb, Fb=F; Pb=P; Rb=R; Ebest=E; pbest=p; end
                end
            end
        otherwise
            if strcmp(name,'Laplacian')
                [~,t0]=edge(X,'zerocross',[],fspecial('laplacian',0));
            else
                [~,t0]=edge(X,lower(name));
            end
            for fa=facs
                p=sprintf('thr=%.4g',fa*t0);
                E=run_filter(X,name,p,lowR);
                [P,R,F]=score_edges(E,T,tol);
                if F>Fb, Fb=F; Pb=P; Rb=R; Ebest=E; pbest=p; end
            end
    end
end

function E = run_filter(X,name,p,lowR)
    switch name
        case 'Canny'
            v=sscanf(p,'sigma=%f, high=%f');
            E=edge(X,'canny',[lowR*v(2) v(2)],v(1));
        case 'LoG'
            v=sscanf(p,'sigma=%f, thr=%f');
            E=edge(X,'log',v(2),v(1));
        case 'Laplacian'
            v=sscanf(p,'thr=%f');
            E=edge(X,'zerocross',v,fspecial('laplacian',0));
        otherwise
            v=sscanf(p,'thr=%f');
            E=edge(X,lower(name),v);
    end
end

function S = canny_steps(X,sigma,H,L)
    S.B=imgaussfilt(X,sigma);
    [S.Gx,S.Gy]=imgradientxy(S.B,'sobel');
    G=hypot(S.Gx,S.Gy);
    S.G=G/max(G(:)+eps);
    th=atan2d(S.Gy,S.Gx);
    th(th<0)=th(th<0)+180;
    sec=mod(round(th/45),4);
    Gp=padarray(S.G,[1 1],0);
    nb=@(dr,dc) Gp((2:end-1)+dr,(2:end-1)+dc);
    keep=(sec==0 & S.G>=nb(0,1) & S.G>=nb(0,-1)) | ...
         (sec==1 & S.G>=nb(1,1) & S.G>=nb(-1,-1)) | ...
         (sec==2 & S.G>=nb(1,0) & S.G>=nb(-1,0)) | ...
         (sec==3 & S.G>=nb(1,-1) & S.G>=nb(-1,1));
    S.N=S.G.*keep;
    S.strong=S.N>=H;
    S.weak=S.N>=L & ~S.strong;
    cand=S.strong | S.weak;
    CC=bwlabel(cand,8);
    ids=unique(CC(S.strong));
    S.E=ismember(CC,ids(ids>0));
end

function O = overlay_lines(base,m,x,ms)
    O=repmat(base,[1 1 3]);
    if ~isempty(m), O=paint(O,m,[0 0.8 0]); end
    if ~isempty(x), O=paint(O,x,[1 0 0]); end
    if ~isempty(ms), O=paint(O,ms,[0 0.3 1]); end
end

function O = paint(O,mask,c)
    for ch=1:3
        tmp=O(:,:,ch);
        tmp(mask)=c(ch);
        O(:,:,ch)=tmp;
    end
end

function add_note(t,note)
    xlabel(t,note,'FontSize',8,'Color',[0.3 0.3 0.3]);
end

function save_fig(f,file)
    exportgraphics(f,file,'Resolution',300);
end

function s = safe_name(s)
    s=regexprep(s,'[^a-zA-Z0-9_-]','_');
end
