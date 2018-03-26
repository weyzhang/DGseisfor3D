!*******************************************************************!
!*  This module initiate surface geometries                        *!
!*                                                                 *!
!*  Author: Ruichao Ye    Email: Ruichao.ye@gmail.com              *!
!*******************************************************************!

!--------------------------------------------------------------------
module surface_mod
!--------------------------------------------------------------------

    use datatype_mod, only : rkind,&
                             rupture,tetmesh_geometry,tetmesh_Domain,&
                             vector_array,tensor_array,&
                             ini_tensor,del_tensor,reset_tensor,&
                             ini_vector,del_vector,reset_vector,&
                             PML_geometry,receivers
    use para_mod,     only : basename,def_pOrder,pNp,Nfp,finalTime,&
                             Fnamelen,src_radius,friction
    use meshfile_mod, only : xmax,xmin,ymax,ymin,zmax,zmin,F2T,&
                             triface
    use geometry_mod, only : rupt_perm,surf_perm,rupt_perm_info
    use bitree_mod,   only : bitree_init,bitree_add,bitree_find,&
                             bitree_del
    use parallel_mod, only : domain_exchange,check_map

    implicit none

!--------------------------------------------------------------------
    contains
!--------------------------------------------------------------------

subroutine surface_Jac(Np,Nfp,Nface,coord,Jac,invJ)
    integer,intent(in) :: Np,Nfp,Nface
    type(vector_array) :: coord
    real(kind=rkind) :: Jac(9,Nface),invJ(9,Nface)
    real(kind=rkind) :: x1,x2,x3,y1,y2,y3,z1,z2,z3,tmp
    real(kind=rkind) :: nx1,nx2,nx3,ny1,ny2,ny3,nz1,nz2,nz3
    integer :: iface,nod1,nod2,nod3
    do iface=1,Nface
        nod1=(iface-1)*Nfp+1
        nod2=(iface-1)*Nfp+Np+1
        nod3=iface*Nfp
        x1=coord%x(nod1);x2=coord%x(nod2);x3=coord%x(nod3)
        y1=coord%y(nod1);y2=coord%y(nod2);y3=coord%y(nod3)
        z1=coord%z(nod1);z2=coord%z(nod2);z3=coord%z(nod3)
        nx1=x2-x1;ny1=y2-y1;nz1=z2-z1
        nx2=x3-x1;ny2=y3-y1;nz2=z3-z1
        nx3=ny1*nz2-ny2*nz1
        ny3=nz1*nx2-nz2*nx1
        nz3=nx1*ny2-nx2*ny1
        tmp=sqrt(nx3**2+ny3**2+nz3**2)
        nx3=nx3/tmp;ny3=ny3/tmp;nz3=nz3/tmp
        Jac(1,iface)=nx1;Jac(2,iface)=nx2;Jac(3,iface)=nx3
        Jac(4,iface)=ny1;Jac(5,iface)=ny2;Jac(6,iface)=ny3
        Jac(7,iface)=nz1;Jac(8,iface)=nz2;Jac(9,iface)=nz3
        tmp=Jac(1,iface)*Jac(5,iface)*Jac(9,iface)&
           +Jac(3,iface)*Jac(4,iface)*Jac(8,iface)&
           +Jac(2,iface)*Jac(6,iface)*Jac(7,iface)&
           -Jac(3,iface)*Jac(5,iface)*Jac(7,iface)&
           -Jac(2,iface)*Jac(4,iface)*Jac(9,iface)&
           -Jac(1,iface)*Jac(6,iface)*Jac(8,iface)
        invJ(1,iface)=(ny2*nz3-ny3*nz2)/4.0d0/tmp
        invJ(2,iface)=(ny3*nz1-ny1*nz3)/4.0d0/tmp
        invJ(3,iface)=(ny1*nz2-ny2*nz1)/4.0d0/tmp
        invJ(4,iface)=(nx3*nz2-nx2*nz3)/4.0d0/tmp
        invJ(5,iface)=(nx1*nz3-nx3*nz1)/4.0d0/tmp
        invJ(6,iface)=(nx2*nz1-nx1*nz2)/4.0d0/tmp
        invJ(7,iface)=(nx2*ny3-nx3*ny2)/4.0d0/tmp
        invJ(8,iface)=(nx3*ny1-nx1*ny3)/4.0d0/tmp
        invJ(9,iface)=(nx1*ny2-nx2*ny1)/4.0d0/tmp
    enddo
end subroutine surface_Jac

subroutine extsurf_init(pNp,Nfp,mesh)
    type(tetmesh_geometry) :: mesh
    integer :: pNp,Nfp
    integer :: iele,j,iface,Nface,fhead,ftail,head,tail,offset
    Nface=0
    do iele=1,mesh%Nhele
        do j=1,4
            if(mesh%fbctype(1,j,iele).eq.1 .and. &
               mesh%fbctype(2,j,iele).eq.1)then
                Nface=Nface+1
                mesh%fbctype(1,j,iele)=3
                mesh%fbctype(2,j,iele)=Nface
            endif
        enddo
    enddo
    mesh%surf%Nface=Nface
    allocate(mesh%surf%nx(Nface))
    allocate(mesh%surf%ny(Nface))
    allocate(mesh%surf%nz(Nface))
    call ini_vector(Nfp*Nface,mesh%surf%coord)
    call ini_vector(Nfp*Nface,mesh%surf%Sn)
    do iele=1,mesh%Nhele
        offset=(iele-1)*pNp
        do j=1,4
            if(mesh%fbctype(1,j,iele).eq.3)then
                iface=mesh%fbctype(2,j,iele)
                mesh%surf%nx(iface)=mesh%nx(j,iele)
                mesh%surf%ny(iface)=mesh%ny(j,iele)
                mesh%surf%nz(iface)=mesh%nz(j,iele)
                head=(j-1)*Nfp+1
                tail=j*Nfp
                fhead=(iface-1)*Nfp+1
                ftail=iface*Nfp
                mesh%surf%coord%x(fhead:ftail)&
                    =mesh%coord%x(mesh%vmapM(head:tail)+offset)
                mesh%surf%coord%y(fhead:ftail)&
                    =mesh%coord%y(mesh%vmapM(head:tail)+offset)
                mesh%surf%coord%z(fhead:ftail)&
                    =mesh%coord%z(mesh%vmapM(head:tail)+offset)
            endif
        enddo
    enddo
end subroutine extsurf_init

subroutine rupture_init(basename,rupt,mesh)
! input
    character(len=Fnamelen),intent(in) :: basename
! output
    type(tetmesh_geometry) :: mesh
    type(rupture) :: rupt
! auxilary
    character(len=Fnamelen) :: filename
    character(len=6) :: ctmp
    integer :: iele,Nface,iface,jface,kface,offset
    integer :: i,j,k,fid,error,flag
    real(kind=rkind) :: rtmp,rerror,nerror,nx,ny,nz,Sn1,Sn2,Sn3,nSn
    real(kind=rkind),allocatable :: a(:)
    real(kind=rkind) :: aa,bb,LL,V0,tau,f0,Vini,psi,tauf
    real(kind=rkind),pointer :: x(:),y(:),z(:)
    integer,allocatable :: ID(:),ID1(:)
    logical :: alive
    real(kind=rkind) :: rface(3)
    real(kind=rkind) :: x2,x3,x4,y2,y3,y4,z2,z3,z4

    write(ctmp,'(I6)')def_pOrder
    ctmp=adjustl(ctmp)

    filename=trim(basename)//'.rupt.p'//trim(ctmp)
    inquire(file=trim(filename),exist=alive)
    if(.not. alive)then
        print*,'error: ',filename,' not exist'
        return
    endif
    fid=1015
    open(unit=fid,file=trim(filename),access='stream',status='old')
    read(fid)Nface
    rupt%globNface=Nface
    if(Nface .le. 0)then
            return
    endif
    allocate(ID(Nface))
    read(fid)ID

    rupt%Nface=0
    ID=-ID
    do iele=1,mesh%Nhele
        do i=1,4
            if(mesh%fbctype(1,i,iele).ne.2)cycle
            iface=mesh%fbctype(2,i,iele)
            if(iface.eq.0)then
                mesh%fbctype(1,i,iele)=1
                mesh%fbctype(2,i,iele)=1
                cycle
            endif
            if(ID(abs(iface)).lt.0)then
                rupt%Nface=rupt%Nface+1
                ID(abs(iface))=rupt%Nface
            endif
            mesh%fbctype(2,i,iele)=sign(ID(abs(iface)),iface)
        enddo
    enddo
    do iele=mesh%Nhele+1,mesh%Nele
        do i=1,4
            if(mesh%fbctype(1,i,iele).ne.2)cycle
            iface=mesh%fbctype(2,i,iele)
            if(iface.eq.0 .or. ID(abs(iface)).lt.0)then
                mesh%fbctype(1,i,iele)=1
                mesh%fbctype(2,i,iele)=1
            else
                mesh%fbctype(2,i,iele)=sign(ID(abs(iface)),iface)
            endif
        enddo
    enddo

    rupt%Nhface=rupt%Nface
    call bitree_init(Nface,1)
    do i=1,Nface
        if(ID(i).gt.0)then
            rface=dble(triface(:,i))
            do j=1,3
                call bitree_add(rface(j:),1,k,0.5d0)
            enddo
        endif
    enddo
    do i=1,Nface
        if(ID(i).le.0)then
            flag=-1
            rface=dble(triface(:,i))
            do j=1,3
                call bitree_find(rface(j:),1,k,0.5d0)
                if(k.gt.0)then
                    flag=1;exit
                endif
            enddo
            if(flag.gt.0)then
                rupt%Nface=rupt%Nface+1
                ID(i)=rupt%Nface
            endif
        endif
    enddo
    call bitree_del(k)

    do i=1,Nface
        if(ID(i).le.0)ID(i)=0
    enddo

    if(rupt%Nface .gt. 0)then

        call rupture_malloc(rupt)

        do i=1,Nface
            if(ID(i).gt.0 .and. ID(i).le.rupt%Nhface)then
                rupt%perm(:,:,ID(i))=rupt_perm(:,:,i)
                if(any(rupt_perm_info(3:4,i).eq.0))&
                        print*,'ERROR: ',F2T(:,i)
            endif
        enddo

        do i=1,Nface
            if(ID(i).gt.0)then
                rupt%globID(ID(i))=i
            endif
        enddo

        ! build up T2E connection
        do iele=1,mesh%Nele
            do i=1,4
                if(mesh%fbctype(1,i,iele).ne.2)cycle
                iface=mesh%fbctype(2,i,iele)
                if(iface.eq.0)cycle
                if(iface.gt.0)then
                    rupt%T2E(1,abs(iface))=iele
                    rupt%T2E(3,abs(iface))=i
                else
                    rupt%T2E(2,abs(iface))=iele
                    rupt%T2E(4,abs(iface))=i
                endif
            enddo
        enddo

        allocate(a(Nfp*Nface))

        ! read in rupture coordinate
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%coord%x)
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%coord%y)
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%coord%z)

        ! read in initial aseismic slip rate
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%a )
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%b )
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%L )
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%V0)
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%f0)
        call readfile_sample(Nface,rupt%Nface,Nfp,ID,fid,a,rupt%dVt)

        ! build up rupture facet connections
        call rupture_avg_init(rupt,Nfp,def_pOrder)

        do iele=1,mesh%Nele
            j=0
            do i=1,4
                if(mesh%fbctype(1,i,iele).eq.2)j=j+1
            enddo
            if(j.ge.2)print*,'warning: element attached to ',j,&
                ' rupture facets'
        enddo

    endif

    deallocate(rupt_perm,rupt_perm_info)
    deallocate(ID)
    close(fid)

    ! verify element to surface map
    call rupture_geometry_check(Nfp,mesh%rupt,mesh)

end subroutine rupture_init

subroutine rupture_malloc(rupt)
    type(rupture) :: rupt
    integer :: i

    allocate(rupt%perm(Nfp,2,rupt%Nface))
    allocate(rupt%T2E(4,rupt%Nface));rupt%T2E=-1
    allocate(rupt%globID(rupt%Nface))

    allocate(rupt%Jac(9,rupt%Nface))
    allocate(rupt%invJac(9,rupt%Nface))

    call ini_vector (Nfp*rupt%Nface,rupt%coord)
    allocate(rupt%a (Nfp*rupt%Nface));rupt%a =0d0
    allocate(rupt%b (Nfp*rupt%Nface));rupt%b =0d0
    allocate(rupt%L (Nfp*rupt%Nface));rupt%L =0d0
    allocate(rupt%V0(Nfp*rupt%Nface));rupt%V0=0d0
    allocate(rupt%f0(Nfp*rupt%Nface));rupt%f0=0d0
    call ini_vector (Nfp*rupt%Nface,rupt%Vt0)
    call ini_vector (Nfp*rupt%Nface,rupt%tau0)
    allocate(rupt%sigma0(Nfp*rupt%Nface));rupt%sigma0=0d0

    allocate(rupt%sigma(Nfp*rupt%Nface));rupt%sigma=0d0
    call ini_vector    (Nfp*rupt%Nface,rupt%tauf)
    call ini_vector    (Nfp*rupt%Nface,rupt%Vt)
    allocate(rupt%dVt  (Nfp*rupt%Nface));rupt%dVt=0d0
    allocate(rupt%psi  (Nfp*rupt%Nface));rupt%psi=0d0
    call ini_vector    (pNp*rupt%Nface,rupt%Um)
    call ini_vector    (pNp*rupt%Nface,rupt%Up)
    call ini_tensor    (pNp*rupt%Nface,rupt%Em,.false.)
    call ini_tensor    (pNp*rupt%Nface,rupt%Ep,.false.)

    call reset_vector(rupt%Um)
    call reset_vector(rupt%Up)
    call reset_tensor(rupt%Em)
    call reset_tensor(rupt%Ep)

    allocate(rupt%f(Nfp*rupt%Nface));rupt%f=0d0
    call ini_vector(Nfp*rupt%Nface,rupt%tau)
    allocate(rupt%crack_t(Nfp*rupt%Nface));rupt%crack_t=finalTime

end subroutine rupture_malloc

subroutine rupture_crack_time(Ndof,Vt,crack_t,time)
    integer,intent(in) :: Ndof
    real(kind=rkind) :: Vt(Ndof),crack_t(Ndof),time
    real(kind=rkind),parameter :: tol=1d-6
    integer :: i
    do i=1,Ndof
        if(crack_t(i).gt.time .and. Vt(i).gt.tol)crack_t(i)=time
    enddo
end subroutine rupture_crack_time

subroutine rupture_avg_init(rupt,Nfp,pOrder)
    type(rupture) :: rupt
    integer :: Nfp,pOrder
    real(kind=rkind) :: coord(3),tol,rtmp
    integer :: i,j,k

    allocate(rupt%nmap(Nfp*rupt%Nface))
    rupt%nmap=-1
    tol=1d100
    do i=1,rupt%Nface
        j=(i-1)*Nfp+1;k=(i-1)*Nfp+pOrder+1
        rtmp=sqrt((rupt%coord%x(j)-rupt%coord%x(k))**2 &
                + (rupt%coord%y(j)-rupt%coord%y(k))**2 &
                + (rupt%coord%z(j)-rupt%coord%z(k))**2 )
        tol=min(tol,rtmp)
        j=i*Nfp
        rtmp=sqrt((rupt%coord%x(j)-rupt%coord%x(k))**2 &
                + (rupt%coord%y(j)-rupt%coord%y(k))**2 &
                + (rupt%coord%z(j)-rupt%coord%z(k))**2 )
        tol=min(tol,rtmp)
        k=(i-1)*Nfp+1
        rtmp=sqrt((rupt%coord%x(j)-rupt%coord%x(k))**2 &
                + (rupt%coord%y(j)-rupt%coord%y(k))**2 &
                + (rupt%coord%z(j)-rupt%coord%z(k))**2 )
        tol=min(tol,rtmp)
    enddo
    tol=tol*1d-3
    call bitree_init(Nfp*rupt%Nface,3)
    do i=1,Nfp*rupt%Nface
        coord(1)=rupt%coord%x(i)
        coord(2)=rupt%coord%y(i)
        coord(3)=rupt%coord%z(i)
        call bitree_add(coord,3,rupt%nmap(i),tol)
    enddo
    call bitree_del(k)
    if(minval(rupt%nmap).le.0)print*,'rupt nmap error'
    allocate(rupt%avg(k),rupt%weigh(k))
    rupt%weigh=0d0
    do i=1,Nfp*rupt%Nface
        rupt%weigh(rupt%nmap(i))=rupt%weigh(rupt%nmap(i))+1d0
    enddo
    if(minval(rupt%weigh).le.0.5)print*,'rupt weigh error'

end subroutine rupture_avg_init

subroutine rupture_geometry_check(Nfp,rupt,mesh)
    type(tetmesh_geometry) :: mesh
    type(rupture) :: rupt
    integer :: Nfp,iele,i,j,k,iface,jface,kface,flag
    real(kind=rkind) :: rerror,nerror,rtmp
    integer,allocatable :: ID(:),ID1(:)
    real(kind=rkind),pointer :: &
        x(:),y(:),z(:),&
        rx(:),ry(:),rz(:)
    real(kind=rkind),parameter :: TOL=1d-5
    ! verify element to surface map
    if(rupt%Nface .gt. 0)then
        rerror=0d0;nerror=0d0
        allocate(ID(Nfp));allocate(ID1(Nfp))
        x=>mesh%coord%x;y=>mesh%coord%y;z=>mesh%coord%z
        rx=>rupt%coord%x;ry=>rupt%coord%y;rz=>rupt%coord%z
        do iele=1,mesh%Nhele
            do i=1,4
                if(mesh%fbctype(1,i,iele).ne.2)cycle
                iface=mesh%fbctype(2,i,iele)
                if(iface.gt.0)then
                    ID=(iface-1)*Nfp+rupt%perm(:,1,iface)
                    flag=1
                else
                    ID=(-iface-1)*Nfp+rupt%perm(:,2,-iface)
                    flag=-1
                endif
                ID1=(iele-1)*pNp+mesh%vmapM((i-1)*Nfp+1:i*Nfp)
                rtmp=sqrt(maxval(&
                      (x(ID1)   -rx(ID))**2+ &
                      (y(ID1)   -ry(ID))**2+ &
                      (z(ID1)   -rz(ID))**2) &
                    /((x(ID1(1))- x(ID1(Nfp)))**2+ &
                      (y(ID1(1))- y(ID1(Nfp)))**2+ &
                      (z(ID1(1))- z(ID1(Nfp)))**2) )
                if(rtmp.gt.TOL)then
                    print*,'error=',iface,i,rtmp,&
                      sqrt((sum(x(ID1))-sum(rx(ID)))**2+&
                           (sum(y(ID1))-sum(ry(ID)))**2+&
                           (sum(z(ID1))-sum(rz(ID)))**2)/Nfp
                    print*,''
                endif
                if(rtmp.gt.rerror)rerror=rtmp
                rtmp=sqrt(mesh%nx(i,iele)**2+mesh%ny(i,iele)**2)
                if(rtmp.gt.nerror)nerror=rtmp
            enddo
        enddo
        if(rerror.ge.TOL)&
            print*,'rupture initiated, error=',rerror,nerror
        do iface=1,rupt%Nhface
            do i=1,2
                iele=rupt%T2E(i,iface)
                jface=rupt%T2E(i+2,iface)
!                ID1(rupt%perm(:,i,iface))=&
!                    mesh%vmapM((jface-1)*Nfp+1:jface*Nfp)+(iele-1)*pNp
!                do j=1,Nfp
!                    ID(j)=(iface-1)*Nfp+j
!                enddo
                ID=(iface-1)*Nfp+rupt%perm(:,i,iface)
                ID1=mesh%vmapM((jface-1)*Nfp+1:jface*Nfp)+(iele-1)*pNp
                rtmp=sqrt(maxval(&
                      (x(ID1)   -rx(ID))**2+ &
                      (y(ID1)   -ry(ID))**2+ &
                      (z(ID1)   -rz(ID))**2) &
                    /((x(ID1(1))- x(ID1(Nfp)))**2+ &
                      (y(ID1(1))- y(ID1(Nfp)))**2+ &
                      (z(ID1(1))- z(ID1(Nfp)))**2) )
                if(rtmp.gt.TOL)then
                    print*,'error=',iface,i,rtmp,&
                      sqrt((sum(x(ID1))-sum(rx(ID)))**2+&
                           (sum(y(ID1))-sum(ry(ID)))**2+&
                           (sum(z(ID1))-sum(rz(ID)))**2)/Nfp
                    print*,''
                endif
                if(rtmp.gt.rerror)rerror=rtmp
            enddo
            rx(ID)=x(ID1)
            ry(ID)=y(ID1)
            rz(ID)=z(ID1)
        enddo
        if(rerror.ge.TOL)&
            print*,'rupture initiated, error=',rerror
        deallocate(ID,ID1)
    endif

end subroutine rupture_geometry_check

subroutine readfile_sample(Nrec,Nsmp,Lrec,flag,fid,buffer,output)
    integer,intent(in) :: Nrec,Nsmp,Lrec,fid
    integer,intent(in) :: flag(Nrec)
    real(kind=rkind),intent(out) :: buffer(Nrec*Lrec),&
                                    output(Nsmp*Lrec)
    integer :: i,j,irec
    read(fid)buffer
    do irec=1,Nrec
        if(flag(irec) .gt. 0)then
            i=(flag(irec)-1)*Lrec
            j=(irec-1)*Lrec
            output(i+1:i+Lrec)=buffer(j+1:j+Lrec)
        endif
    enddo
end subroutine readfile_sample

subroutine rupt_recording(recvs,rupt,Nfp)
    type(receivers) :: recvs
    type(rupture) :: rupt
    integer,intent(in) :: Nfp
    integer :: i,iele,head,tail

    recvs%Nrecord=recvs%Nrecord+1
    if(recvs%Nrecv.le.0)return
    do i=1,recvs%Nrecv
        iele=recvs%recv2ele(i)
        head=(iele-1)*Nfp+1;tail=iele*Nfp
        ! Vt
        recvs%rec_buffer(1,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%Vt%x(head:tail))
        recvs%rec_buffer(2,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%Vt%y(head:tail))
        recvs%rec_buffer(3,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%Vt%z(head:tail))
        ! tauf
        recvs%rec_buffer(4,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%tauf%x(head:tail))
        recvs%rec_buffer(5,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%tauf%y(head:tail))
        recvs%rec_buffer(6,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%tauf%z(head:tail))
        ! sigma
        recvs%rec_buffer(7,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%sigma(head:tail))
        ! f
        recvs%rec_buffer(8,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%f(head:tail))
        ! psi
        recvs%rec_buffer(9,recvs%Nrecord,i)=&
            dot_product(recvs%rnodalw(:,i),rupt%psi(head:tail))
    enddo
end subroutine rupt_recording

subroutine rupture_average(Nfp,subdomain,rupt,a)
    type(tetmesh_Domain)   :: subdomain
    type(rupture) :: rupt
    real(kind=rkind) :: a(:)
    integer :: Nfp,N_DD_Conn,ierr,i
    call domain_exchange(subdomain,rupt%SRtype,a,&
        rupt%SRtype%send_req,rupt%SRtype%recv_req,1100)
    N_DD_Conn=rupt%SRtype%host%N_DD_Conn
    if(N_DD_Conn.gt.0)&
    call MPI_Waitall(N_DD_Conn,&
        rupt%SRtype%send_req,rupt%SRtype%sta,ierr)
    N_DD_Conn=rupt%SRtype%gost%N_DD_Conn
    if(N_DD_Conn.gt.0)&
    call MPI_Waitall(N_DD_Conn,&
        rupt%SRtype%recv_req,rupt%SRtype%sta,ierr)
    rupt%avg=0d0
    do i=1,Nfp*rupt%Nface
        rupt%avg(rupt%nmap(i))=rupt%avg(rupt%nmap(i))+a(i)
    enddo
    rupt%avg=rupt%avg/rupt%weigh
    do i=1,Nfp*rupt%Nface
        a(i)=rupt%avg(rupt%nmap(i))
    enddo
end subroutine rupture_average

subroutine check_rupt_map(Nfp,subdomain,rupt)
    integer :: Nfp
    type(tetmesh_Domain)   :: subdomain
    type(rupture) :: rupt
    real(kind=rkind) :: err
    if(rupt%Nface.gt.0)then
        call check_map(subdomain,rupt%SRtype,&
            rupt%coord%x,rupt%tau%x,&
            rupt%Nface*Nfp,rupt%Nhface*Nfp,1)
        call rupture_average(Nfp,subdomain,rupt,rupt%tau%x)
        err=maxval(abs(rupt%tau%x-rupt%coord%x))
        if(err.gt.1d-16)print*,'x error=',err

        call check_map(subdomain,rupt%SRtype,&
            rupt%coord%y,rupt%tau%y,&
            rupt%Nface*Nfp,rupt%Nhface*Nfp,1)
        call rupture_average(Nfp,subdomain,rupt,rupt%tau%y)
        err=maxval(abs(rupt%tau%y-rupt%coord%y))
        if(err.gt.1d-16)print*,'y error=',err

        call check_map(subdomain,rupt%SRtype,&
            rupt%coord%z,rupt%tau%z,&
            rupt%Nface*Nfp,rupt%Nhface*Nfp,1)
        call rupture_average(Nfp,subdomain,rupt,rupt%tau%z)
        err=maxval(abs(rupt%tau%z-rupt%coord%z))
        if(err.gt.1d-16)print*,'z error=',err
        call reset_vector(rupt%tau)
    endif

end subroutine check_rupt_map

end module surface_mod
