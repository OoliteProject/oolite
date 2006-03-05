#!/usr/bin/python

"""
This script takes a .mesh file from the Meshwork
and exports a .dat file containing the same trimesh.

Colour for the faces is set to flat grey (127,127,127)
and surface normals calculated for each triangle.
"""

import sys, string, math

inputfilenames = sys.argv[1:]
print "converting..."
print inputfilenames
for inputfilename in inputfilenames:
	outputfilename = inputfilename.lower().replace(".mesh",".dat")
	print inputfilename+"->"+outputfilename
	inputfile = open(inputfilename,"r")
	lines = inputfile.read().splitlines(0)
	outputfile = open(outputfilename,"w")
	mode = 'SKIP'
	vertex_lines_out = ['VERTEX\n']
	faces_lines_out = ['FACES\n']
	n_verts = 0
	n_faces = 0
	skips = 0
	vertex=[]
	face=[]
	textureCounter = 0
	for line in lines:
		if (mode == 'VERTEX'):
			coordinates = string.split(line, '\t')	# split line by tabs
			if (len(coordinates) == 4):
				n_verts = n_verts + 1
				vertex_lines_out.append(coordinates[1]+', '+coordinates[2]+', '+coordinates[3]+'\n')
				vertex.append( (float(coordinates[1]), float(coordinates[2]), float(coordinates[3])) )
		elif (mode == 'FACES'):
			tokens = string.split(line, '\t')	# split line by tabs
			if (len(tokens) == 3):
				n_faces = n_faces + 1
				v1 = int(tokens[0])
				v2 = int(tokens[1])
				v3 = int(tokens[2])
				d0 = (vertex[v2][0]-vertex[v1][0], vertex[v2][1]-vertex[v1][1], vertex[v2][2]-vertex[v1][2])
				d1 = (vertex[v3][0]-vertex[v2][0], vertex[v3][1]-vertex[v2][1], vertex[v3][2]-vertex[v2][2])
				xp = (d0[1]*d1[2]-d0[2]*d1[1], d0[2]*d1[0]-d0[0]*d1[2], d0[0]*d1[1]-d0[1]*d1[0])
				det = 1.0 / math.sqrt(xp[0]*xp[0] + xp[1]*xp[1] + xp[2]*xp[2])
				norm = (xp[0]*det, xp[1]*det, xp[2]*det)
				face.append((v1,v2,v3))
				faces_lines_out.append('127,127,127,\t%f,%f,%f,\t3,\t%d,%d,%d\n' % (norm[0],norm[1],norm[2],v1,v2,v3))
		elif (mode == 'TEXTURE'):
			tokens = string.split(line, '\t')	# split line by tabs
			if (len(tokens) == 3):
				v1 = int(tokens[0])
				uu = float(tokens[1])
				vv = float(tokens[2])
		elif (mode == 'SKIP'):
			skips = skips + 1
		if (line[:8] == 'VERTICES'):
			mode = 'VERTEX'
		if (line[:8] == 'MATERIAL'):
			mode = 'FACES'
			interpretTexture = 0
			tokens = string.split(line, '\t')	# split line by tabs
			if (len(tokens) == 15):
				name_parts = string.split(tokens[0],' ')
				name_parts.append("texture%d.png" % textureCounter)
				textureName = name_parts[1]
				if (tokens[5] == '4'):
					interpretTexture = 1
		if (line[:5] == 'EDGES'):
			mode = 'SKIP'
		if (line[:3] == 'UVS'):
			if (interpretTexture):
				mode = 'TEXTURE'
			else:
				mode = 'SKIP'
	outputfile.write('NVERTS %d\n' % n_verts)
	outputfile.write('NFACES %d\n' % n_faces)
	outputfile.write('\n')
	outputfile.writelines(vertex_lines_out)
	outputfile.write('\n')
	outputfile.writelines(faces_lines_out)
	outputfile.write('\n')
	outputfile.write('END\n')
	outputfile.close();
print "done"
print ""
#
#	end
#
