using System.Numerics;
namespace Further.Core;

// CPU generation is safe to run off the render thread. No engine objects cross this boundary.
public sealed record TerrainMeshData(Vector3[] Positions,Vector3[] Normals,float[] Trail,int[] Indices,IReadOnlyList<Decoration> Scenery,IReadOnlyList<MeadowTuft> Meadow)
{
    public static TerrainMeshData Generate(Island island,bool detailed)
    {
        int count=detailed?161:25;float step=island.Radius*2.65f/(count-1);
        var grid=PrivateSources.BorderedGrid(count,step,(x,z)=>World.Height(island,island.Center+new Vector2(x,z)));
        var positions=new Vector3[count*count];var normals=new Vector3[positions.Length];var trails=new float[positions.Length];var indices=new int[(count-1)*(count-1)*6];
        var routes=IslandLayout.Routes(island);
        for(int z=0;z<count;z++)for(int x=0;x<count;x++)
        {
            int i=z*count+x;var p=grid[(z+1)*(count+2)+x+1];positions[i]=p;
            var left=grid[(z+1)*(count+2)+x];var right=grid[(z+1)*(count+2)+x+2];var back=grid[z*(count+2)+x+1];var front=grid[(z+2)*(count+2)+x+1];
            normals[i]=Vector3.Normalize(new(left.Y-right.Y,2*step,back.Y-front.Y));trails[i]=IslandLayout.TrailDistance(new(p.X,p.Z),routes);
        }
        int k=0;for(int z=0;z<count-1;z++)for(int x=0;x<count-1;x++)
        {
            int a=z*count+x;indices[k++]=a;indices[k++]=a+1;indices[k++]=a+count;indices[k++]=a+1;indices[k++]=a+count+1;indices[k++]=a+count;
        }
        return new(positions,normals,trails,indices,detailed?IslandLayout.Scenery(island):[],detailed?IslandLayout.Meadow(island):[]);
    }
}
