function [u, errors, res_errors, errors_per_breg, res_errors_per_breg, iters ] = bregman_cs_framelet_3d(f, m, n, k, A, At, nu, exci, mu, lambda, gamma, maxiter, img, video)
%bregman_cs_framelet
%
%We minimize nu*|nabla u| + exci*|Fu| st Au = f
%F is a framelet transform
%
% A -- a function handle to the sampling operator
% At -- A^t
%
% nu -- tune the TV strength
% exci -- tune the framelet strength
%
% mu -- the exterior constraint split
% gamma -- the framelet split
% lambda -- the TV split
% ie mu,lambda, and gamma are parameters for
% mu*At(A(x)) + lambda*laplacian + gamma*x
% which we solve with pcg
%
% maxiter -- how many times we can apply A before stopping the algorithm
%
% img is the exact image, we only use it to update the errors as you go.
%

%don't know if this exists already or not...
norm3 = @(x) sqrt(trapz(trapz(trapz(abs(x).^2))));


%1 is for Haar, 2 is for framelet, 3 is for cubic framelet
%Haar sucks. 2 works best, 3 is slower and worse.
%[D,Dt]=GenerateFrameletFilter(2);

%more levels is better? I don't know. Experimentally, more levels is slow
%and worse quality. Hmmm.
%n_level = 1;

%check that we chose sane parameters
if nu == 0
    assert(lambda == 0);
end
if exci == 0
    assert(gamma == 0);
end

%create the AtA operator. for some reason lk convolution like this (not conv2) works best.
%lk = zeros(m,n);
%lk(1,1) = 4;lk(1,2)=-1;lk(2,1)=-1;lk(m,1)=-1;lk(1,n)=-1;
%AtA = @(x) mu*At(A(x)) + lambda*reshape(ifft2(fft2(reshape(x,[m n])).*fft2(lk)), [m*n 1]) + gamma*x;

%2D
%Lap = laplacian([m n], {'P','P'}); %negative laplacian
%AtA = @(x) mu*At(A(x)) + lambda*Lap*x + gamma*x;

%3D
lk = zeros(m,n);
%lk(1,1) = 4;lk(1,2)=-1;lk(2,1)=-1;lk(m,1)=-1;lk(1,n)=-1;
%AtA = @(x) mu*At(A(x)) + lambda*reshape(ifft2(fft2(reshape(x,[m n])).*fft2(lk)), [m*n 1]) + gamma*x;


%3D, still seems to work for 2D data
fprintf('3D Laplacian matrix with 7-point stencil\n');
Lap = laplacian([m n k], {'P','P','P'});
AtA = @(x) mu*At(A(x)) + lambda*Lap*x + gamma*x;


%set initial guesses
%U = FraDecMultiLevel(zeros(m,n),D,n_level);
%dw = U;
%bw = U;

%initial guess.
u = reshape(At(f),[m n k]);

%initial splitting vectors
dx = zeros(size(u));
dy = zeros(size(u));
dz = zeros(size(u));
bx = zeros(size(u));
by = zeros(size(u));
bz = zeros(size(u));

%constrained, replace f with fl and update after each unconstrained
fl = f;
res_errors = [];
errors = [];
errors_per_breg = [];
res_errors_per_breg = [];
iters = [];

% start the optimization.
% the outer loop is constraint enforcement
ell = 0;
while(sum(iters) < maxiter)
    ell = ell+1;
    %unconstrained step, 5 is overkill.
    for kay=1:3
        %update u
        %rhsD = FraRecMultiLevel(SubFrameletArray(dw,bw),Dt,n_level);
        rhs = mu.*reshape(At(reshape(fl, [numel(fl) 1])),[m n k]);
        rhs = rhs + lambda*(Deriv(dx - bx,1,true) + Deriv(dy - by,2,true) + Deriv(dz - bz,3,true));
        rhs = rhs + gamma.*u;
        
        %this is where all the computation happens
        yy = reshape(rhs,[numel(rhs) 1]);
        [u,~,~,iterc] = pcg(AtA, yy, 1e-6, 100);
        iters = [iters iterc];
        fprintf('pcg iters: %i\n',iterc);
        
        u = reshape(u,[m n k]);
        
        %update d's
        %U = AddFrameletArray(FraDecMultiLevel(u,D,n_level),bw); %Du + b_k
        %if gamma ~= 0 && exci ~= 0
        %    dw = ShrinkFramelet(U,1/(gamma/exci));
        %end
        
        if lambda ~=0 && nu ~= 0
            [dx,dy,dz] = shrink3( Deriv(u,1,false)+bx, Deriv(u,2,false)+by, Deriv(u,3,false)+bz, 1/(lambda/nu));
        end
        
        %update b's
        %bw = SubFrameletArray(U,dw); %U-d_k
        bx = bx + (Deriv(u,1,false) - dx);
        by = by + (Deriv(u,2,false) - dy);
        bz = bz + (Deriv(u,3,false) - dz);
        
        res_errors = [res_errors norm(A(reshape(u, [m*n*k 1])) - f,'fro')/norm(f,'fro')];
        errors = [errors norm3(u./max(u(:)) - img./max(img(:)))];
        
    end
    fl = fl + f - A(reshape(u, [m*n*k 1]));
    res_errors_per_breg = [res_errors_per_breg norm(A(reshape(u, [m*n*k 1])) - f,'fro')/norm(f,'fro')];
    errors_per_breg = [errors_per_breg norm3(u./max(u(:)) - img./max(img(:)))];
    
    if (video && randi(10) == 3)
        if(ndims(u)==3)
        %%
        whitebg('k');       
        h = vol3d('cdata',abs(u),'texture','3D');
        view(3);
        axis tight;  daspect([1 1 .4])
        alphamap('rampup');
        %%
        if(ell==1)
            alphamap(.02 .* alphamap);
        end
        
        pause(.03);
        else if (ndims(u)==2)
                subplot(2,2,1);
                imagesc(real(img));
                title('exact image');
        
                subplot(2,2,2);
                imagesc(real(u));
                title('current reconstruction');
        
                subplot(2,2,4);
                errorfig = abs(u/max(u(:)) - img/max(img(:)));
                imagesc(errorfig);
                title('reconstruction error');
        
                subplot(6,2,7);
                semilogy(errors_per_breg);
                title('image domain error per breg');
                subplot(6,2,11);
                semilogy(res_errors_per_breg,'r.-');
                title('residual error per breg');
        
                colormap hot;
                pause(0.03);
        
            end
        end
    end
    fprintf('breg step ell = %i error (u-img): %f Ax iter numer: %i \n', [ell errors(end) sum(iters)]);
    fprintf('breg step ell = %i res error : %f Ax iter numer: %i \n---\n', [ell res_errors(end) sum(iters)]);
    


end


end

