#!/usr/bin/python

"""
This script takes a .mesh file from the Meshwork
and exports a .obj file containing the same trimesh.

A .mtl file is created for texture materials.

No surface normals are calculated.
"""

import sys, string, math

inputfilenames = sys.argv[1:]
print "converting..."
print inputfilenames
for inputfilename in inputfilenames:
	outputfilename = inputfilename.lower().replace(".mesh",".obj")
	materialfilename = inputfilename.lower().replace(".mesh",".mtl")
	mtllibname = string.split(materialfilename, "/")[-1]
	print inputfilename+"->"+outputfilename+" & "+materialfilename
	inputfile = open(inputfilename,"r")
	lines = inputfile.read().splitlines(0)
	outputfile = open(outputfilename,"w")
	materialfile = open(materialfilename,"w")
	mode = 'SKIP'
	vertex_lines_out = ['# vertices...\n']
	faces_lines_out = ['# faces...\n']
	n_verts = 0
	n_faces = 0
	n_uvs = 0
	skips = 0
	vertex=[]
	face=[]
	uv_lines_out=['# texture uvs...\n']
	textures=[]
	normalForVertex=[]
	uvForVertex=[]
	uvIndexForKey={}
	uvsForTexture={}
	textureForFace=[]
	textureCounter = 0
	for line in lines:
		if (mode == 'VERTEX'):
			coordinates = string.split(line, '\t')	# split line by tabs
			if (len(coordinates) == 4):
				n_verts = n_verts + 1
				vertex_lines_out.append('v %.5f %.5f %.5f\n' % (float(coordinates[1]), float(coordinates[2]), float(coordinates[3])))
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
				if (interpretTexture):
					textureForFace.append(textureName)
		elif (mode == 'TEXTURE'):
			tokens = string.split(line, '\t')	# split line by tabs
			if (len(tokens) == 3):
				v1 = int(tokens[0])
				uu = 1.0 - float(tokens[1])
				vv = 1.0 - float(tokens[2])
				if ((uu > 1.0)|(uu < 0.0)|(vv > 1.0)|(vv < 0.0)):
					uu = 0.0
					vv = 0.0
				uv_key = 'vt %.5f %.5f\n' % (uu, vv)
				uv_index = n_uvs
				if (uvIndexForKey.has_key(uv_key)):
					# existing uv coordinates
					uv_index = uvIndexForKey[uv_key]
				else:
					# new, unique uv coordinates
					uvIndexForKey[uv_key] = uv_index
					uv_lines_out.append(uv_key)
					n_uvs = n_uvs + 1
				uvsForTexture[textureName][v1] = (uu,vv,uv_index)
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
					textures.append(textureName)
					uvsForTexture[textureName] = n_verts * [[]]
		if (line[:5] == 'EDGES'):
			mode = 'SKIP'
		if (line[:3] == 'UVS'):
			if (interpretTexture):
				mode = 'TEXTURE'
			else:
				mode = 'SKIP'
	outputfile.write('# exported using Mesh2Obj.py (C) Giles Williams 2005\n')
	outputfile.write('mtllib %s\n' % mtllibname)
	outputfile.write('o exported_mesh\n')
	outputfile.write('# number of vertices %d\n' % n_verts)
	outputfile.write('# number of faces %d\n' % n_faces)
	outputfile.write('# number of texture uvs %d\n' % n_uvs)
	outputfile.writelines(vertex_lines_out)
	outputfile.writelines(uv_lines_out)
	# for each texture file / material we have to write out a group of faces
	#
	materialfile.write('# exported using Mesh2Obj.py (C) Giles Williams 2005\n')
	# check that we have textures for every vertex...
	okayToWriteTexture = 1
	print "uvsForTexture :"
	print uvsForTexture
	if (len(textureForFace) != len(face)):
		okayToWriteTexture = 0
	outputfile.write('# groups ...\n')
	group_ctr = 1
	for texture in textures:
		if (texture == ''):
			okayToWriteTexture = 0
		# if we're all clear then write out the texture uv coordinates on a 256x256 texture
		if (okayToWriteTexture):
			materialfile.write('newmtl material%d_auv\nNs 100.000\nd 1.00000\nillum 2\n' % group_ctr)
			materialfile.write('Kd 1.00000 1.00000 1.00000\nKa 1.00000 1.00000 1.00000\nKs 1.00000 1.00000 1.00000\n')
			materialfile.write('map_Kd %s\n\n' % texture)
			outputfile.write('g group_%d\n' % group_ctr)
			outputfile.write('usemtl material%d_auv\n' % group_ctr)
			group_ctr = group_ctr + 1
			outputfile.write('# uses texture \'%s\'\n' % texture)
			for i in range(0, len(face)):
				facet = face[i]
				texture_for_face = textureForFace[i]
				if (texture == texture_for_face):
					uvForVertex = uvsForTexture[texture]
					outputfile.write('f %d/%d/ %d/%d/ %d/%d/\n' % (facet[0] + 1, uvForVertex[facet[0]][2] + 1, facet[1] + 1, uvForVertex[facet[1]][2] + 1, facet[2] + 1, uvForVertex[facet[2]][2] + 1, ))
				# endif
			# next i
		# endif
	# next texture
	outputfile.close();
	materialfile.close();
print "done"
print ""
#
#	end
#
