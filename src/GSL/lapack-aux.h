#define DVEC(A) int A##n, double*A##p
#define CVEC(A) int A##n, double*A##p
#define DMAT(A) int A##r, int A##c, double* A##p
#define CMAT(A) int A##r, int A##c, double* A##p

// const pointer versions for the parameters 
#define KDVEC(A) int A##n, const double*A##p
#define KCVEC(A) int A##n, const double*A##p
#define KDMAT(A) int A##r, int A##c, const double* A##p
#define KCMAT(A) int A##r, int A##c, const double* A##p 

int svd_l_R(KDMAT(x),DMAT(u),DVEC(s),DMAT(v));
int svd_l_Rdd(KDMAT(x),DMAT(u),DVEC(s),DMAT(v));

int svd_l_C(KCMAT(a),CMAT(u),DVEC(s),CMAT(v));

int eig_l_C(KCMAT(a),CMAT(u),CVEC(s),CMAT(v));

int eig_l_R(KDMAT(a),DMAT(u),CVEC(s),DMAT(v));

int eig_l_S(KDMAT(a),DVEC(s),DMAT(v));

int eig_l_H(KCMAT(a),DVEC(s),CMAT(v));