FOLDERS = compvis             \
          compvis/experiments \
          compvis/pose        \
          compvis/pose/maze   \
          compvis/stereo      \
          compvis/pano        \
          compvis/classify    \
          compvis/tutorial    \

all:
	for dir in $(FOLDERS); do (cd $$dir; ${MAKE} all); done
